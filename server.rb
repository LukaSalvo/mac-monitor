require 'sinatra'
require 'json'

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

require 'etc'

# --- UTILITAIRES SYSTÈME ---
def get_system_info
  {
    os: RbConfig::CONFIG['host_os'],
    platform: RbConfig::CONFIG['host_cpu'],
    cpu_cores: Etc.nprocessors
  }
end

def get_cpu_usage
  return 0.0 unless File.exist?('/proc/stat')
  
  # Lecture 1
  cpu1 = File.read('/proc/stat').lines.first.split.map(&:to_i)
  sleep 0.5 # Court délai pour calculer le delta
  # Lecture 2
  cpu2 = File.read('/proc/stat').lines.first.split.map(&:to_i)
  
  # [user, nice, system, idle, iowait, irq, softirq, steal, guest, guest_nice]
  # Idle est à l'index 4 (valeur 3 du tableau split car "cpu" est le 0)
  # Mais split donne: ["cpu", "user", "nice", "sys", "idle", ...]
  # Donc indices : user=1, nice=2, sys=3, idle=4
  
  idle1 = cpu1[4] + cpu1[5] # idle + iowait
  total1 = cpu1[1..].sum
  
  idle2 = cpu2[4] + cpu2[5]
  total2 = cpu2[1..].sum
  
  diff_idle = idle2 - idle1
  diff_total = total2 - total1
  
  return 0.0 if diff_total == 0
  
  used_pct = (1.0 - diff_idle.to_f / diff_total.to_f) * 100
  used_pct.round(1)
end

def get_memory_usage
  return { total: 0, used: 0, percent: 0 } unless File.exist?('/proc/meminfo')
  
  meminfo = {}
  File.read('/proc/meminfo').each_line do |line|
    parts = line.split(':')
    next unless parts.length == 2
    key = parts[0].strip
    value = parts[1].strip.to_i * 1024 # Convertir kB en Bytes
    meminfo[key] = value
  end
  
  total = meminfo['MemTotal'] || 0
  available = meminfo['MemAvailable'] 
  
  # Si MemAvailable n'est pas dispo (vieux noyaux), approximation : free + buffers + cached
  unless available
    free = meminfo['MemFree'] || 0
    buffers = meminfo['Buffers'] || 0
    cached = meminfo['Cached'] || 0
    available = free + buffers + cached
  end
  
  used = total - available
  percent = total > 0 ? ((used.to_f / total.to_f) * 100).round(1) : 0.0
  
  { total: total, used: used, percent: percent }
end

def get_cpu_temperature
  begin
    # Linux
    [
      '/sys/class/thermal/thermal_zone0/temp',
      '/sys/devices/virtual/thermal/thermal_zone0/temp'
    ].each do |path|
      if File.exist?(path)
        raw = File.read(path).to_i
        # Parfois c'est en millidegrés, parfois en degrés. Si > 1000, c'est milli.
        return (raw > 150 ? raw / 1000.0 : raw).round(1)
      end
    end
    
    # macOS (Apple Silicon & Intel) - Best effort via sysctl (requiert privileges souvent, mais essayons user space)
    if RbConfig::CONFIG['host_os'] =~ /darwin/
      # Pas de méthode standard fiable sans root/gem externe, mais on peut tenter
      # Pour Intel: machdep.xcpm.cpu_thermal_level (pas une vraie temp)
      return nil 
    end

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

get '/api/processes' do
  content_type :json
  sort = params[:sort] || 'cpu'
  limit = (params[:limit] || 20).to_i
  
  processes = []
  begin
    # Format ps: pid, user, cpu, mem, command
    # linux 'ps' args: -e (all), -o (format)
    # sorting via ps is easiest: --sort=-%cpu or --sort=-%mem
    sort_arg = sort == 'mem' ? '--sort=-%mem' : '--sort=-%cpu'
    
    output = `ps -eo pid,user,%cpu,%mem,comm #{sort_arg} | head -n #{limit + 1}`
    output.lines.drop(1).each do |line|
      parts = line.split
      next if parts.length < 5
      processes << {
        pid: parts[0],
        user: parts[1],
        cpu: parts[2].to_f,
        mem: parts[3].to_f,
        command: parts[4..].join(' ')
      }
    end
  rescue => e
    puts "Process Error: #{e.message}"
  end
  { processes: processes }.to_json
end

def get_disks_via_sys_filesystem
  d = []
  Sys::Filesystem.mounts.each { |m| 
    next if m.mount_type =~ /tmpfs|proc|devfs|sysfs|squashfs/
    begin
      s = Sys::Filesystem.stat(m.mount_point)
      t = s.blocks * s.block_size
      next if t < 10**9 # Ignorer petits volumes < 1GB
      d << { device: m.name, mountpoint: m.mount_point, total_bytes: t, used_bytes: t-(s.blocks_free*s.block_size) }
    rescue; end
  }
  d
end

def get_disks_via_df
  d = []
  begin
    # df -B1 output: Filesystem 1B-blocks Used Available Use% Mounted on
    `df -B1 -x tmpfs -x devtmpfs -x squashfs`.lines.drop(1).each do |line|
      parts = line.split
      next if parts.length < 6
      
      total = parts[1].to_i
      used = parts[2].to_i
      mount = parts[5]
      
      next if total < 10**9 # Ignore < 1GB
      
      d << { 
        device: parts[0], 
        mountpoint: mount, 
        total_bytes: total, 
        used_bytes: used 
      }
    end
  rescue; end
  d
end

get '/api/disks' do
  content_type :json
  # Try Sys::Filesystem first, fallback to df
  disks = get_disks_via_sys_filesystem
  if disks.empty?
    disks = get_disks_via_df
  end
  disks.to_json
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
  local_ip = get_local_ip
  
  # Method 1: Nmap (Preferred)
  if File.executable?(NMAP_PATH)
    begin
      subnet = local_ip.split('.')[0..2].join('.') + '.0/24'
      xml_output = `sudo #{NMAP_PATH} -sn -oX - #{subnet} 2>/dev/null`
      if !xml_output.empty? && xml_output.start_with?('<')
        doc = REXML::Document.new(xml_output)
        doc.elements.each('nmaprun/host') do |host|
          ip = host.elements["address[@addrtype='ipv4']"]&.attributes['addr']
          next unless ip
          
          hostname_el = host.elements["hostnames/hostname"]
          hostname = hostname_el ? hostname_el.attributes['name'] : "Inconnu"
          
          devices << { ip: ip, hostname: hostname, status: 'up', is_local: (ip == local_ip) }
        end
        return devices unless devices.empty?
      end
    rescue => e; puts "Nmap Error: #{e.message}"; end
  end

  # Method 2: Fallback to ARP / ip neigh
  begin
    # ip neigh output: 192.168.1.1 dev eth0 lladdr 00:11:22:33:44:55 STALE
    `ip neigh`.each_line do |line|
      parts = line.split
      ip = parts[0]
      next unless ip =~ /^\d+\.\d+\.\d+\.\d+$/ # IPv4 only
      
      # Try to resolve hostname via simple host command or just use IP
      hostname = "Inconnu" # resolving takes time, skip for speed in fallback
      
      state = parts.last
      next if state == 'FAILED'
      
      devices << { ip: ip, hostname: hostname, status: 'up', is_local: (ip == local_ip), source: 'arp' }
    end
    
    # Add self if not in ARP
    unless devices.any? { |d| d[:is_local] }
      devices << { ip: local_ip, hostname: Socket.gethostname, status: 'up', is_local: true, source: 'local' }
    end
    
  rescue => e; puts "ARP Error: #{e.message}"; end
  
  devices
end


def get_network_stats
  rx = 0
  tx = 0
  begin
    File.read('/proc/net/dev').lines.drop(2).each do |line|
      parts = line.split
      # interface is parts[0] sans ':'
      iface = parts[0].tr(':', '')
      next if iface == 'lo' # ignore loopback
      
      # col 1 = RX bytes, col 9 = TX bytes (if parts[0] includes colon, otherwise offset might vary but split usually handles it)
      # /proc/net/dev format:
      # face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
      # wlo1: 1408...
      # If split gives ["wlo1:", "140...", ...] -> bytes is index 1
      
      rx += parts[1].to_i
      tx += parts[9].to_i
    end
  rescue; end
  { rx: rx, tx: tx }
end

def get_root_disk_usage
  # Fallback to df for root path /
  result = { total: 0, used: 0, percent: 0 }
  begin
    # df -B1 /
    output = `df -B1 /`.lines.last.split
    # Filesystem 1B-blocks Used Available Use% Mounted on
    total = output[1].to_i
    used = output[2].to_i
    result = { 
      total: total, 
      used: used, 
      percent: (total > 0 ? (used.to_f / total * 100).round(1) : 0) 
    }
  rescue; end
  result
end

# --- THREAD DE COLLECTE ---
Thread.new do
  system_info = get_system_info # Collecter une fois au démarrage
  
  loop do
    begin
      # On dort au début pour permettre au `get_cpu_usage` de faire sa propre pause si besoin
      # ou sleep après. Ici get_cpu_usage a un sleep(0.5).
      
      mem = get_memory_usage
      cpu = get_cpu_usage
      net = get_network_stats
      disk = get_root_disk_usage
      
      current_data = {
        timestamp: Time.now.to_i, 
        hostname: Socket.gethostname,
        platform: system_info[:platform], # "x86_64" ou "arm64"
        os: system_info[:os],             # "linux-gnu" ou "darwin..."
        cpu_cores: system_info[:cpu_cores],
        cpu_usage: cpu, 
        cpu_temp: get_cpu_temperature,
        memory_total_bytes: mem[:total], memory_used_bytes: mem[:used],
        memory_percent: mem[:percent],
        uptime_seconds: (File.read('/proc/uptime').split[0].to_i rescue 0),
        
        # New Data Feeds
        network_recv: net[:rx],
        network_sent: net[:tx],
        disk_total_bytes: disk[:total],
        disk_used_bytes: disk[:used],
        disk_percent: disk[:percent]
      }
      
      HISTORY << current_data
      HISTORY.shift if HISTORY.length > MAX_HISTORY
      
      # Log périodique (pas à chaque seconde pour éviter de spammer)
      if Time.now.to_i % 60 == 0
        File.open(LOG_FILE, 'a') { |f| f.puts "[#{Time.now}] INFO: CPU #{current_data[:cpu_usage]}% | Mem #{current_data[:memory_percent]}% | Net RX: #{current_data[:network_recv]}" }
      end
      
      sleep 1.5 # +0.5s dans get_cpu_usage = ~2s total cycle
    rescue => e; puts "Loop Error: #{e.message}"; sleep 1; end
  end
end