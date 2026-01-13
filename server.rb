require 'sinatra'
require 'json'
require 'vmstat'
require 'sys/filesystem'
require 'socket'
require 'rexml/document'
require 'pony'
require 'rbconfig'

# Configuration
set :port, 3000
set :bind, '0.0.0.0'
set :public_folder, 'public'

HISTORY = []
MAX_HISTORY = 3600
NETWORK_SCAN_CACHE = { data: nil, timestamp: 0 }
SCAN_CACHE_DURATION = 0 
LOG_FILE = File.expand_path('app.log', __dir__)
NMAP_PATH = "/usr/bin/nmap" 

# --- VÉRIFICATION DES MISES À JOUR (Multi-OS) ---
def check_updates
  results = { system_updates: [], gem_updates: [], os: "Unknown" }
  host_os = RbConfig::CONFIG['host_os']
  
  if host_os =~ /linux/
    results[:os] = "Linux (Debian/Ubuntu)"
    output = `apt list --upgradable 2>/dev/null | grep /`
    results[:system_updates] = output.split("\n").reject(&:empty?).map { |l| l.split("/")[0] }
  elsif host_os =~ /darwin/
    results[:os] = "macOS"
    output = `brew outdated --short 2>/dev/null`
    results[:system_updates] = output.split("\n").reject(&:empty?)
  end

  # Vérification des Gems via Bundler
  gem_output = `bundle outdated --parseable 2>/dev/null`
  results[:gem_updates] = gem_output.split("\n").map { |l| l.split(" ")[1] }.compact
  results
end

# --- UTILITAIRES SYSTÈME ---
def get_cpu_usage
  begin
    output = `top -b -n 1 | grep -E '^%?Cpu\\(s\\):'` 
    if output =~ /(\d+\.\d+|\d+)\s*id/ 
      return (100.0 - $1.to_f).round(1)
    end
  rescue; end
  0.0
end

def get_cpu_temperature
  begin
    temp_path = '/sys/class/thermal/thermal_zone0/temp'
    return (File.read(temp_path).to_i / 1000.0).round(1) if File.exist?(temp_path)
  rescue; end
  nil
end

def get_local_ip
  ip = Socket.ip_address_list.detect { |addr| addr.ipv4? && !addr.ipv4_loopback? }&.ip_address
  ip || `hostname -I | awk '{print $1}'`.strip
end

# --- ROUTES ---
get '/' do send_file File.join(settings.public_folder, 'index.html') end
get '/api/system' do content_type :json; HISTORY.to_json end
get '/api/updates' do content_type :json; check_updates.to_json end

get '/api/disks' do
  content_type :json
  d = []
  Sys::Filesystem.mounts.each { |m| 
    next if m.mount_type =~ /tmpfs|proc|devfs/
    begin
      s = Sys::Filesystem.stat(m.mount_point)
      t = s.blocks * s.block_size
      next if t < 10**9
      d << { device: m.name, mountpoint: m.mount_point, total_bytes: t, used_bytes: t-(s.blocks_free*s.block_size) }
    rescue; end
  }
  d.to_json
end

get '/api/network/scan' do content_type :json; { devices: scan_network, local_ip: get_local_ip }.to_json end

get '/api/logs' do
  content_type :json
  if File.exist?(LOG_FILE)
    lines = `tail -n 100 #{LOG_FILE}`.split("\n")
    logs = lines.reverse.map { |l| { level: l.include?('ERROR') ? 'ERROR' : 'INFO', message: l } }
    { logs: logs }.to_json
  else
    { error: "Log file not found" }.to_json
  end
end

# --- SCAN RÉSEAU ---
def scan_network
  devices = []
  begin
    local_ip = get_local_ip
    subnet = local_ip.split('.')[0..2].join('.') + '.0/24'
    xml_output = `sudo #{NMAP_PATH} -sn -oX - #{subnet} 2>/dev/null`
    if !xml_output.empty?
      doc = REXML::Document.new(xml_output)
      doc.elements.each('nmaprun/host') do |host|
        ip = host.elements["address[@addrtype='ipv4']"]&.attributes['addr']
        next unless ip
        devices << { ip: ip, hostname: host.elements["hostnames/hostname"]&.attributes['name'] || "Inconnu", status: 'up', is_local: (ip == local_ip) }
      end
    end
  rescue; end
  devices
end

# --- THREAD DE COLLECTE ---
Thread.new do
  loop do
    begin
      sleep 2
      vm = Vmstat.snapshot
      mem_tot = vm.memory.total_bytes
      mem_used = vm.memory.active_bytes || (mem_tot - vm.memory.free_bytes)
      
      current_data = {
        timestamp: Time.now.to_i, hostname: Socket.gethostname,
        cpu_usage: get_cpu_usage, cpu_temp: get_cpu_temperature,
        memory_total_bytes: mem_tot, memory_used_bytes: mem_used,
        memory_percent: ((mem_used.to_f/mem_tot.to_f)*100).round(1),
        uptime_seconds: Vmstat.boot_time ? (Time.now - Vmstat.boot_time).to_i : 0
      }
      
      HISTORY << current_data
      HISTORY.shift if HISTORY.length > MAX_HISTORY
      File.open(LOG_FILE, 'a') { |f| f.puts "[#{Time.now}] INFO: Snapshot CPU #{current_data[:cpu_usage]}%" }
    rescue => e; puts "Loop Error: #{e.message}"; end
  end
end