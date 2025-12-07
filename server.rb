require 'sinatra'
require 'json'
require 'vmstat'
require 'sys/filesystem'
require 'socket'
require 'rexml/document'

# --- CONFIGURATION ---
set :port, 3000
set :bind, '0.0.0.0'
set :public_folder, 'public'

# --- VARIABLES GLOBALES ---
HISTORY = []
MAX_HISTORY = 3600
NETWORK_SCAN_CACHE = { data: nil, timestamp: 0 }

# Stockage permanent des alertes (Historique)
# On ne le vide jamais, on garde juste les 10 derniers
EVENT_ALERTS = [] 
KNOWN_MACS = [] 

# --- CHEMIN NMAP ---
NMAP_PATH = "/opt/homebrew/bin/nmap" 

# --- UTILITAIRES SYSTÈME ---
def get_cpu_usage
  begin
    output = `top -l 2 -n 0 | grep "CPU usage" | tail -1`
    return ($1.to_f + $2.to_f).round(1) if output =~ /([\d\.]+)% user,\s+([\d\.]+)% sys/
  rescue; return 0.0; end
  return 0.0
end

def get_cpu_temperature
  begin
    output = `osx-cpu-temp 2>/dev/null`
    return $1.to_f if $?.success? && output =~ /(\d+\.\d+)°C/
  rescue; end
  nil
end

def get_local_ip
  ip = Socket.ip_address_list.detect { |addr| addr.ipv4? && !addr.ipv4_loopback? && !addr.ipv4_multicast? }&.ip_address
  unless ip
    ip = `ipconfig getifaddr en0`.strip
    ip = nil if ip.empty?
  end
  return ip
end

# --- SCAN RÉSEAU ---
def scan_network
  if NETWORK_SCAN_CACHE[:data] && (Time.now.to_i - NETWORK_SCAN_CACHE[:timestamp]) < 5
    return NETWORK_SCAN_CACHE[:data]
  end

  devices = []
  
  begin
    local_ip = get_local_ip
    
    if local_ip && File.exist?(NMAP_PATH)
      subnet = local_ip.split('.')[0..2].join('.') + '.0/24'
      cmd = "sudo #{NMAP_PATH} -sn -T4 -oX - #{subnet}"
      xml_output = `#{cmd} 2>/dev/null`
      
      if $?.success? && !xml_output.empty?
        doc = REXML::Document.new(xml_output)
        doc.elements.each('nmaprun/host') do |host|
          status = host.elements['status']&.attributes['state']
          next unless status == 'up'
          
          ip_elem = host.elements["address[@addrtype='ipv4']"]
          ip = ip_elem ? ip_elem.attributes['addr'] : nil
          next unless ip 
          
          mac_elem = host.elements["address[@addrtype='mac']"]
          mac = mac_elem ? mac_elem.attributes['addr'] : nil
          vendor = mac_elem ? mac_elem.attributes['vendor'] : nil
          
          hostname_elem = host.elements["hostnames/hostname"]
          hostname = hostname_elem ? hostname_elem.attributes['name'] : nil
          
          is_local = (ip == local_ip)
          
          devices << {
            ip: ip,
            hostname: hostname || "Inconnu",
            mac: mac || (is_local ? "THIS-DEVICE" : "--"),
            vendor: vendor || (is_local ? "Apple Inc." : "--"),
            status: 'up',
            is_local: is_local
          }
        end
      end
    end
  rescue => e
    puts "DEBUG: Erreur scan: #{e.message}"
  end
  
  if devices.empty? && (local = get_local_ip)
     devices << { ip: local, hostname: Socket.gethostname, mac: "THIS-DEVICE", vendor: "Apple Inc.", status: 'up', is_local: true }
  end

  NETWORK_SCAN_CACHE[:data] = devices
  NETWORK_SCAN_CACHE[:timestamp] = Time.now.to_i
  
  devices
end

def get_processes(sort_by = 'cpu', limit = 20)
  processes = []
  begin
    output = `ps aux`
    lines = output.split("\n")
    return [] if lines.length < 2
    lines[1..-1].each do |line|
      parts = line.split(/\s+/, 11)
      next if parts.length < 11
      processes << { user: parts[0], pid: parts[1].to_i, cpu: parts[2].to_f, mem: parts[3].to_f, command: parts[10] }
    end
    sort_by == 'cpu' ? processes.sort_by! { |p| -p[:cpu] } : processes.sort_by! { |p| -p[:mem] }
    processes.take(limit)
  rescue; [] end
end

# --- GESTION DES ALERTES ---
def check_alerts(data)
  current_alerts = []
  
  # 1. Alertes TEMPS RÉEL (Peuvent apparaître et disparaître)
  if data[:cpu_usage] > 80
    current_alerts << { type: 'warning', category: 'cpu', message: "High CPU: #{data[:cpu_usage]}%", timestamp: Time.now.to_i }
  end
  if data[:disk_percent] > 90
    current_alerts << { type: 'critical', category: 'disk', message: "Disk Full: #{data[:disk_percent]}%", timestamp: Time.now.to_i }
  end
  
  # 2. Alertes HISTORIQUE (Restent affichées)
  # On combine les alertes actives + les 10 dernières alertes de l'historique
  # .reverse pour avoir les plus récentes en haut
  return current_alerts + EVENT_ALERTS.last(10).reverse
end

# --- THREAD 1 : STATS SYSTÈME (Toutes les 2 sec) ---
Thread.new do
  loop do
    begin
      sleep 2
      cpu = get_cpu_usage
      vm = Vmstat.snapshot
      mem_tot = vm.memory.total_bytes
      mem_used = vm.memory.active_bytes || (mem_tot - vm.memory.free_bytes)
      n_s = 0; n_r = 0
      vm.network_interfaces.each { |i| next if i.loopback?; n_s += i.out_bytes; n_r += i.in_bytes }
      
      d_stat = { t: 0, u: 0, p: 0 }
      begin
        m = Sys::Filesystem.mounts.find { |mn| mn.mount_point == '/' }
        if m
          s = Sys::Filesystem.stat(m.mount_point)
          d_stat[:t] = s.blocks * s.block_size
          d_stat[:u] = d_stat[:t] - (s.blocks_free * s.block_size)
          d_stat[:p] = ((d_stat[:u].to_f / d_stat[:t].to_f) * 100).round(1)
        end
      rescue; end

      HISTORY << {
        timestamp: Time.now.to_i, hostname: Socket.gethostname, platform: RUBY_PLATFORM, os: RbConfig::CONFIG['host_os'],
        cpu_cores: vm.cpus.length, cpu_usage: cpu, cpu_temp: get_cpu_temperature,
        memory_total_bytes: mem_tot, memory_used_bytes: mem_used, memory_percent: ((mem_used.to_f/mem_tot.to_f)*100).round(1),
        disk_total_bytes: d_stat[:t], disk_used_bytes: d_stat[:u], disk_percent: d_stat[:p],
        network_sent: n_s, network_recv: n_r, uptime_seconds: Vmstat.boot_time ? (Time.now - Vmstat.boot_time).to_i : 0
      }
      HISTORY.shift if HISTORY.length > MAX_HISTORY
    rescue => e; puts "Error Stats loop: #{e.message}"; end
  end
end

# --- THREAD 2 : SCAN RÉSEAU AUTOMATIQUE (Toutes les 60 sec) ---
Thread.new do
  sleep 5 # Pause au démarrage
  loop do
    begin
      devices = scan_network
      current_macs = devices.map { |d| d[:mac] }.reject { |m| m == "THIS-DEVICE" || m == "--" }

      if KNOWN_MACS.empty?
        # Premier scan : on mémorise tout sans alerter
        KNOWN_MACS.replace(current_macs)
      else
        # Scans suivants : on compare
        new_devices_macs = current_macs - KNOWN_MACS
        
        new_devices_macs.each do |mac|
          dev_info = devices.find { |d| d[:mac] == mac }
          name = dev_info[:hostname] == "Inconnu" ? dev_info[:ip] : dev_info[:hostname]
          vendor = dev_info[:vendor]
          
          msg = "New Device: #{name} (#{vendor})"
          
          # AJOUT À L'HISTORIQUE PERSISTANT
          EVENT_ALERTS << {
            type: 'info',
            category: 'network',
            message: msg,
            timestamp: Time.now.to_i
          }
          
          # On garde seulement les 20 derniers en mémoire pour ne pas saturer
          EVENT_ALERTS.shift if EVENT_ALERTS.length > 20
        end
        
        # On met à jour la liste connue
        KNOWN_MACS.concat(new_devices_macs)
      end
    rescue => e
      puts "Error Auto-Scan loop: #{e.message}"
    end
    sleep 60
  end
end

# --- ROUTES ---
get '/' do send_file File.join(settings.public_folder, 'index.html') end
get '/api/system' do content_type :json; HISTORY.to_json end
get '/api/disks' do
  content_type :json
  d = []
  Sys::Filesystem.mounts.each { |m| 
    next if m.mount_type =~ /tmpfs|proc|devfs/
    begin; s=Sys::Filesystem.stat(m.mount_point); t=s.blocks*s.block_size; next if t < 10**9; d << { device: m.name, mountpoint: m.mount_point, total_bytes: t, used_bytes: t-(s.blocks_free*s.block_size) }; rescue; end
  }
  d.to_json
end
get '/api/network' do content_type :json; i=[]; Vmstat.snapshot.network_interfaces.each{|x| next if x.loopback?; i<<{interface:x.name, bytes_sent:x.out_bytes, bytes_recv:x.in_bytes}}; i.to_json end

get '/api/network/scan' do 
  content_type :json 
  { devices: scan_network, local_ip: get_local_ip }.to_json 
end

# Nouvelle route pour l'auto-refresh du tableau
get '/api/network/latest' do
  content_type :json
  { 
    devices: NETWORK_SCAN_CACHE[:data] || [], 
    timestamp: NETWORK_SCAN_CACHE[:timestamp],
    local_ip: get_local_ip
  }.to_json
end

get '/api/processes' do content_type :json; sort=params[:sort]||'cpu'; limit=(params[:limit]||20).to_i; list=get_processes(sort,limit); {processes:list, count:list.length}.to_json end
post '/api/processes/:pid/kill' do content_type :json; Process.kill('TERM', params[:pid].to_i); {success:true}.to_json rescue {success:false}.to_json end

# Route Alertes : Renvoie Toujours l'historique
get '/api/alerts' do 
  content_type :json
  alerts = HISTORY.empty? ? [] : check_alerts(HISTORY.last)
  { alerts: alerts, timestamp: Time.now.to_i }.to_json 
end