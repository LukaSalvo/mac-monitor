require 'sinatra'
require 'json'
require 'vmstat'
require 'sys/filesystem'
require 'socket'
require 'rexml/document'
require 'pony' # Ajout de Pony pour l'envoi d'email

# Configuration
set :port, 3000
set :bind, '0.0.0.0'
set :public_folder, 'public'

HISTORY = []
MAX_HISTORY = 3600
NETWORK_SCAN_CACHE = { data: nil, timestamp: 0 }
SCAN_CACHE_DURATION = 0 

# --- NOUVEAUX CHEMINS ET CONFIGURATION ---
LOG_FILE = File.expand_path('app.log', __dir__)
# Vérifiez avec 'which nmap' si c'est bien celui-là
NMAP_PATH = "/opt/homebrew/bin/nmap" 

# --- FONCTIONNALITÉS AVANCÉES ---

# Configuration Pony (Email) - REMPLACER CES VALEURS
# Vous aurez besoin d'un service SMTP (Gmail, SendGrid, etc.)
def send_alert_email(subject, body)
  puts "DEBUG: Tentative d'envoi d'email..."
  begin
    Pony.mail({
      :to => 'votre_email_de_reception@exemple.com', 
      :from => 'monitor@votre-domaine.com',
      :subject => "[System Monitor Alert] #{subject}",
      :body => body,
      :via => :smtp,
      :via_options => {
        :address => 'smtp.gmail.com', # EXEMPLE: Changer pour votre SMTP
        :port => '587',
        :user_name => 'votre_compte_smtp', # EXEMPLE: Votre adresse ou utilisateur SMTP
        :password => 'votre_mot_de_passe_app', # EXEMPLE: Mot de passe d'application ou secret SMTP
        :authentication => :plain,
        :enable_starttls_auto => true
      }
    })
    puts "DEBUG: Email envoyé avec succès."
  rescue => e
    puts "ERROR: Échec de l'envoi d'email: #{e.message}"
  end
end

# --- UTILITAIRES ---
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

# --- SCAN RÉSEAU VIA XML (ROBUSTE) ---
def scan_network
  # Cache check (désactivé pour l'instant via SCAN_CACHE_DURATION = 0)
  if NETWORK_SCAN_CACHE[:data] && (Time.now.to_i - NETWORK_SCAN_CACHE[:timestamp]) < SCAN_CACHE_DURATION
    return NETWORK_SCAN_CACHE[:data]
  end

  devices = []
  
  begin
    local_ip = get_local_ip
    
    if local_ip && File.exist?(NMAP_PATH)
      subnet = local_ip.split('.')[0..2].join('.') + '.0/24'
      puts "DEBUG: Scan XML lancé sur #{subnet}..."
      
      # Commande avec -oX - pour sortir du XML
      cmd = "sudo #{NMAP_PATH} -sn -T4 -oX - #{subnet}"
      
      # CORRECTION CRITIQUE DE LA SYNTAXE : 
      # On exécute la commande complète, y compris la redirection d'erreur
      xml_output = `#{cmd} 2>/dev/null` 
      
      if $?.success? && !xml_output.empty?
        # Parsing du XML
        doc = REXML::Document.new(xml_output)
        
        doc.elements.each('nmaprun/host') do |host|
          # État (up/down)
          status = host.elements['status']&.attributes['state']
          next unless status == 'up'
          
          # IP
          ip_elem = host.elements["address[@addrtype='ipv4']"]
          ip = ip_elem ? ip_elem.attributes['addr'] : nil
          next unless ip 
          
          # MAC & Vendor
          mac_elem = host.elements["address[@addrtype='mac']"]
          mac = mac_elem ? mac_elem.attributes['addr'] : nil
          vendor = mac_elem ? mac_elem.attributes['vendor'] : nil
          
          # Hostname
          hostname_elem = host.elements["hostnames/hostname"]
          hostname = hostname_elem ? hostname_elem.attributes['name'] : nil
          
          # Détection si c'est nous
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
      else
        puts "DEBUG: Échec de la commande Nmap ou sortie vide."
      end
    else
      puts "DEBUG: IP locale non trouvée ou Nmap introuvable."
    end
  rescue => e
    puts "DEBUG: Erreur critique Ruby : #{e.message}"
    puts e.backtrace.first
  end
  
  # Si la liste est vide mais qu'on a une IP locale, on s'ajoute au moins nous-même
  if devices.empty? && (local = get_local_ip)
     devices << { ip: local, hostname: Socket.gethostname, mac: "THIS-DEVICE", vendor: "Apple Inc.", status: 'up', is_local: true }
  end

  puts "DEBUG: #{devices.length} appareils trouvés."
  
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

# Mise à jour: Déclenchement de l'email pour les alertes CRITIQUES
def check_alerts(data)
  alerts = []
  if data[:cpu_usage] > 80
    alerts << { type: 'warning', category: 'cpu', message: "High CPU: #{data[:cpu_usage]}%", timestamp: Time.now.to_i }
  end
  
  if data[:disk_percent] > 90
    msg = "Disk Full: #{data[:disk_percent]}%"
    alerts << { type: 'critical', category: 'disk', message: msg, timestamp: Time.now.to_i }
    
    # ENVOI D'EMAIL EN CAS D'ALERTE CRITIQUE
    send_alert_email("CRITICAL Disk Alert", "The disk usage is at #{data[:disk_percent]}% on #{data[:hostname] || 'Monitoring Host'}. Action required!")
  end
  alerts
end

# --- THREAD LOOP ---
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

      current_data = {
        timestamp: Time.now.to_i, hostname: Socket.gethostname, platform: RUBY_PLATFORM, os: RbConfig::CONFIG['host_os'],
        cpu_cores: vm.cpus.length, cpu_usage: cpu, cpu_temp: get_cpu_temperature,
        memory_total_bytes: mem_tot, memory_used_bytes: mem_used, memory_percent: ((mem_used.to_f/mem_tot.to_f)*100).round(1),
        disk_total_bytes: d_stat[:t], disk_used_bytes: d_stat[:u], disk_percent: d_stat[:p],
        network_sent: n_s, network_recv: n_r, uptime_seconds: Vmstat.boot_time ? (Time.now - Vmstat.boot_time).to_i : 0
      }

      # Écriture dans un fichier de log minimal (pour démo)
      File.open(LOG_FILE, 'a') do |f|
        f.puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] INFO: System snapshot taken. CPU: #{current_data[:cpu_usage]}%, Mem: #{current_data[:memory_percent]}%"
      end
      
      HISTORY << current_data
      HISTORY.shift if HISTORY.length > MAX_HISTORY
    rescue => e; puts "Error loop: #{e.message}"; end
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
get '/api/network/scan' do content_type :json; { devices: scan_network, local_ip: get_local_ip }.to_json end
get '/api/processes' do content_type :json; sort=params[:sort]||'cpu'; limit=(params[:limit]||20).to_i; list=get_processes(sort,limit); {processes:list, count:list.length}.to_json end
post '/api/processes/:pid/kill' do content_type :json; Process.kill('TERM', params[:pid].to_i); {success:true}.to_json rescue {success:false}.to_json end
get '/api/alerts' do content_type :json; HISTORY.empty? ? {alerts:[]}.to_json : {alerts:check_alerts(HISTORY.last), timestamp:Time.now.to_i}.to_json end

# NOUVELLE ROUTE : Lecture et analyse des logs
get '/api/logs' do
  content_type :json
  
  if File.exist?(LOG_FILE)
    # Lire les 100 dernières lignes 
    lines = `tail -n 100 #{LOG_FILE}`.split("\n")
    
    # Analyse simple pour remonter des niveaux et inverser l'ordre
    logs = lines.reverse.map do |line|
      level = 'INFO'
      # Cette analyse est très basique et peut être améliorée
      level = 'ERROR' if line.include?('Error') || line.include?('Fail') || line.include?('FATAL')
      { level: level, message: line }
    end
    
    { logs: logs, count: logs.length }.to_json
  else
    { logs: [], count: 0, error: "Log file not found at #{LOG_FILE}" }.to_json
  end
end