require 'sinatra'
require 'json'
require 'vmstat'
require 'sys/filesystem'
require 'socket'

# Configuration du serveur
set :port, 3000
set :bind, '0.0.0.0'
set :public_folder, 'public'

# Stockage de l'historique en mémoire
HISTORY = []
MAX_HISTORY = 3600

Thread.new do
  previous_snapshot = Vmstat.snapshot
  
  loop do
    begin
      # MODIFICATION : On ralentit la collecte pour moins charger le CPU (3 secondes)
      sleep 3 
      
      current_snapshot = Vmstat.snapshot
      
      # --- CALCUL CPU (Méthode Delta Optimisée) ---
      # On additionne les ticks de tous les coeurs
      prev_total = previous_snapshot.cpus.sum { |c| c.user + c.system + c.nice + c.idle }
      curr_total = current_snapshot.cpus.sum { |c| c.user + c.system + c.nice + c.idle }
      
      prev_idle = previous_snapshot.cpus.sum(&:idle)
      curr_idle = current_snapshot.cpus.sum(&:idle)
      
      diff_total = curr_total - prev_total
      diff_idle = curr_idle - prev_idle
      
      cpu_usage = 0
      if diff_total > 0
        raw_usage = (diff_total - diff_idle) / diff_total.to_f
        cpu_usage = (raw_usage * 100).round(1)
      end
      
      # Mise à jour de la référence
      previous_snapshot = current_snapshot

      # --- LE RESTE RESTE PAREIL ---
      mem_total = current_snapshot.memory.total_bytes
      mem_used = current_snapshot.memory.active_bytes || (mem_total - current_snapshot.memory.free_bytes)

      net_sent = 0
      net_recv = 0
      current_snapshot.network_interfaces.each do |iface|
        next if iface.loopback?
        net_sent += iface.out_bytes
        net_recv += iface.in_bytes
      end

      root_mount = Sys::Filesystem.mounts.find { |m| m.mount_point == '/' } || Sys::Filesystem.mounts.first
      disk_stat = Sys::Filesystem.stat(root_mount.mount_point)
      
      disk_total = disk_stat.blocks * disk_stat.block_size
      disk_free = disk_stat.blocks_free * disk_stat.block_size
      disk_used = disk_total - disk_free
      disk_percent = ((disk_used.to_f / disk_total.to_f) * 100).round(1)

      data_point = {
        timestamp: Time.now.to_i,
        hostname: Socket.gethostname,
        platform: RUBY_PLATFORM,
        os: RbConfig::CONFIG['host_os'],
        cpu_cores: current_snapshot.cpus.length,
        cpu_usage: cpu_usage,
        memory_total_bytes: mem_total,
        memory_used_bytes: mem_used,
        memory_percent: ((mem_used.to_f / mem_total.to_f) * 100).round(1),
        disk_total_bytes: disk_total,
        disk_used_bytes: disk_used,
        disk_percent: disk_percent,
        network_sent: net_sent,
        network_recv: net_recv,
        uptime_seconds: Vmstat.boot_time ? (Time.now - Vmstat.boot_time).to_i : 0
      }

      HISTORY << data_point
      HISTORY.shift if HISTORY.length > MAX_HISTORY

    rescue StandardError => e
      puts "Erreur: #{e.message}"
    end
  end
end

# --- ROUTES ---

get '/' do
  send_file File.join(settings.public_folder, 'index.html')
end

get '/api/system' do
  content_type :json
  HISTORY.to_json
end

get '/api/disks' do
  content_type :json
  disks = []
  Sys::Filesystem.mounts.each do |mount|
    begin
      next if mount.mount_type =~ /tmpfs|devtmpfs|proc|sysfs|squashfs/ 
      stat = Sys::Filesystem.stat(mount.mount_point)
      total = stat.blocks * stat.block_size
      next if total < 100 * 1024 * 1024 
      disks << {
        device: mount.name,
        mountpoint: mount.mount_point,
        total_bytes: total,
        used_bytes: total - (stat.blocks_free * stat.block_size),
        type: mount.mount_type
      }
    rescue; end
  end
  disks.to_json
end

get '/api/network' do
  content_type :json
  interfaces = []
  Vmstat.snapshot.network_interfaces.each do |iface|
    next if iface.loopback?
    interfaces << { interface: iface.name, bytes_sent: iface.out_bytes, bytes_recv: iface.in_bytes }
  end
  interfaces.to_json
end