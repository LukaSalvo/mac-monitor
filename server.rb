require 'sinatra'
require 'json'
require 'vmstat'
require 'sys/filesystem'
require 'socket'
require 'rexml/document'
require 'rbconfig'

# --- CONFIGURATION ---
set :port, 3000
set :bind, '0.0.0.0'
set :public_folder, 'public'

# --- DÉTECTION OS ---
def os
  @os ||= (
    host_os = RbConfig::CONFIG['host_os']
    case host_os
    when /mswin|msys|mingw|cygwin|bccwin|wince|emc/
      :windows
    when /darwin|mac os/
      :macosx
    when /linux/
      :linux
    else
      :unknown
    end
  )
end

# --- VARIABLES GLOBALES ---
HISTORY = []
MAX_HISTORY = 3600
NETWORK_SCAN_CACHE = { data: nil, timestamp: 0 }
EVENT_ALERTS = [] 
KNOWN_MACS = [] 

# --- CHEMIN NMAP DYNAMIQUE ---
# On cherche nmap dans le système, sinon on garde le chemin par défaut mac ou linux
def find_nmap
  path = `which nmap`.strip
  return path unless path.empty?
  return "/opt/homebrew/bin/nmap" if os == :macosx
  return "/usr/bin/nmap"
end
NMAP_PATH = find_nmap

# --- UTILITAIRES SYSTÈME ---
def get_cpu_usage
  begin
    if os == :macosx
      output = `top -l 2 -n 0 | grep "CPU usage" | tail -1`
      return ($1.to_f + $2.to_f).round(1) if output =~ /([\d\.]+)% user,\s+([\d\.]+)% sys/
    elsif os == :linux
      # Méthode Linux via /proc/stat (plus fiable et léger que top)
      cpu_stats = File.read("/proc/stat").lines.first.split.map(&:to_f)
      # [user, nice, system, idle, iowait, irq, softirq, steal]
      idle = cpu_stats[4]
      total = cpu_stats[1..].sum
      
      # On a besoin d'une diff, on stocke dans une variable de classe ou on fait simple :
      # Pour l'instant, on utilise une commande top simplifiée pour Linux si /proc/stat est trop complexe sans état
      output = `top -bn 2 | grep "Cpu(s)" | tail -1`
      # Format Linux top: %Cpu(s): 10.5 us,  3.2 sy...
      if output =~ /([\d\.]+)\s*us,\s*([\d\.]+)\s*sy/
        return ($1.to_f + $2.to_f).round(1)
      end
    end
  rescue; return 0.0; end
  return 0.0
end

def get_cpu_temperature
  begin
    if os == :macosx
      output = `osx-cpu-temp 2>/dev/null`
      return $1.to_f if $?.success? && output =~ /(\d+\.\d+)°C/
    elsif os == :linux
      # Essai standard via thermal_zone
      temp = File.read("/sys/class/thermal/thermal_zone0/temp").to_f / 1000
      return temp.round(1)
    end
  rescue; end
  nil
end

def get_local_ip
  # Méthode Ruby universelle en priorité
  ip = Socket.ip_address_list.detect { |addr| addr.ipv4? && !addr.ipv4_loopback? && !addr.ipv4_multicast? }&.ip_address
  
  unless ip
    if os == :macosx
      ip = `ipconfig getifaddr en0`.strip
    elsif os == :linux
      ip = `hostname -I | awk '{print $1}'`.strip
    end
    ip = nil if ip&.empty?
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
      # On utilise sudo si nécessaire, attention sur linux il faut configurer sudoers ou lancer en root
      # Sur debian, souvent nmap nécessite root pour le scan ARP (-sn) complet
      cmd_prefix = (Process.uid == 0) ? "" : "sudo "
      
      subnet = local_ip.split('.')[0..2].join('.') + '.0/24'
      cmd = "#{cmd_prefix}#{NMAP_PATH} -sn -T4 -oX - #{subnet}"
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
            vendor: vendor || (is_local ? "Linux/Apple" : "--"),
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
     devices << { ip: local, hostname: Socket.gethostname, mac: "THIS-DEVICE", vendor: "System", status: 'up', is_local: true }
  end

  NETWORK_SCAN_CACHE[:data] = devices
  NETWORK_SCAN_CACHE[:timestamp] = Time.now.to_i
  
  devices
end

def get_processes(sort_by = 'cpu', limit = 20)
  processes = []
  begin
    # ps aux fonctionne généralement sur Mac et Linux (procps)
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
  if data[:cpu_usage] > 80
    current_alerts << { type: 'warning', category: 'cpu', message: "High CPU: #{data[:cpu_usage]}%", timestamp: Time.now.to_i }
  end
  if data[:disk_percent] > 90
    current_alerts << { type: 'critical', category: 'disk', message: "Disk Full: #{data[:disk_percent]}%", timestamp: Time.now.to_i }
  end
  return current_alerts + EVENT_ALERTS.last(10).reverse
end

# --- THREAD 1 : STATS SYSTÈME ---
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

# --- THREAD 2 : SCAN RÉSEAU ---
Thread.new do
  sleep 5
  loop do
    begin
      devices = scan_network
      current_macs = devices.map { |d| d[:mac] }.reject { |m| m == "THIS-DEVICE" || m == "--" }

      if KNOWN_MACS.empty?
        KNOWN_MACS.replace(current_macs)
      else
        new_devices_macs = current_macs - KNOWN_MACS
        new_devices_macs.each do |mac|
          dev_info = devices.find { |d| d[:mac] == mac }
          name = dev_info[:hostname] == "Inconnu" ? dev_info[:ip] : dev_info[:hostname]
          vendor = dev_info[:vendor]
          
          msg = "New Device: #{name} (#{vendor})"
          EVENT_ALERTS << { type: 'info', category: 'network', message: msg, timestamp: Time.now.to_i }
          EVENT_ALERTS.shift if EVENT_ALERTS.length > 20
        end
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
    # Filtre amélioré pour Linux (snap, docker, etc.)
    next if m.mount_type =~ /tmpfs|proc|devfs|sysfs|cgroup|squashfs/
    begin; s=Sys::Filesystem.stat(m.mount_point); t=s.blocks*s.block_size; next if t < 10**9; d << { device: m.name, mountpoint: m.mount_point, total_bytes: t, used_bytes: t-(s.blocks_free*s.block_size) }; rescue; end
  }
  d.to_json
end
get '/api/network' do content_type :json; i=[]; Vmstat.snapshot.network_interfaces.each{|x| next if x.loopback?; i<<{interface:x.name, bytes_sent:x.out_bytes, bytes_recv:x.in_bytes}}; i.to_json end
get '/api/network/scan' do content_type :json; { devices: scan_network, local_ip: get_local_ip }.to_json end
get '/api/network/latest' do content_type :json; { devices: NETWORK_SCAN_CACHE[:data] || [], timestamp: NETWORK_SCAN_CACHE[:timestamp], local_ip: get_local_ip }.to_json end
get '/api/processes' do content_type :json; sort=params[:sort]||'cpu'; limit=(params[:limit]||20).to_i; list=get_processes(sort,limit); {processes:list, count:list.length}.to_json end
post '/api/processes/:pid/kill' do content_type :json; Process.kill('TERM', params[:pid].to_i); {success:true}.to_json rescue {success:false}.to_json end
get '/api/alerts' do content_type :json; alerts = HISTORY.empty? ? [] : check_alerts(HISTORY.last); { alerts: alerts, timestamp: Time.now.to_i }.to_json end