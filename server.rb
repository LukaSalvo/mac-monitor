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


# --- HELPERS OS ---
def is_mac?
  RbConfig::CONFIG['host_os'] =~ /darwin/
end

def is_linux?
  RbConfig::CONFIG['host_os'] =~ /linux/
end

# --- UTILITAIRES SYSTÈME ---
def get_system_info
  {
    os: RbConfig::CONFIG['host_os'],
    platform: RbConfig::CONFIG['host_cpu'],
    cpu_cores: Etc.nprocessors
  }
end

def get_cpu_usage
  if is_linux? && File.exist?('/proc/stat')
    # Lecture 1
    cpu1 = File.read('/proc/stat').lines.first.split.map(&:to_i)
    sleep 0.5 
    # Lecture 2
    cpu2 = File.read('/proc/stat').lines.first.split.map(&:to_i)
    
    idle1 = cpu1[4] + cpu1[5] # idle + iowait
    total1 = cpu1[1..].sum
    
    idle2 = cpu2[4] + cpu2[5]
    total2 = cpu2[1..].sum
    
    diff_idle = idle2 - idle1
    diff_total = total2 - total1
    
    return 0.0 if diff_total == 0
    ((1.0 - diff_idle.to_f / diff_total.to_f) * 100).round(1)
  elsif is_mac?
    # macOS: top -l 1 est un peu lent (1s), on utilise une technique plus rapide si possible
    # Fallback robuste : parser top (instantané via sysctl est complexe sans C extension)
    begin
        # top -l 1 -n 0 : 1 sample, 0 processes displayed (faster)
        output = `top -l 1 -n 0 | grep "CPU usage"`
        # CPU usage: 10.5% user, 20.0% sys, 69.5% idle
        if output =~ /([0-9.]+)% user,\s+([0-9.]+)% sys/
          user = $1.to_f
          sys = $2.to_f
          (user + sys).round(1)
        else
          0.0
        end
    rescue
        0.0
    end
  else
    0.0
  end
end

def get_memory_usage
  if is_linux? && File.exist?('/proc/meminfo')
    meminfo = {}
    File.read('/proc/meminfo').each_line do |line|
      parts = line.split(':')
      next unless parts.length == 2
      key = parts[0].strip
      value = parts[1].strip.to_i * 1024
      meminfo[key] = value
    end
    
    total = meminfo['MemTotal'] || 0
    available = meminfo['MemAvailable'] 
    
    unless available
      free = meminfo['MemFree'] || 0
      buffers = meminfo['Buffers'] || 0
      cached = meminfo['Cached'] || 0
      available = free + buffers + cached
    end
    
    used = total - available
    percent = total > 0 ? ((used.to_f / total.to_f) * 100).round(1) : 0.0
    
    { total: total, used: used, percent: percent }
  elsif is_mac?
    # Total RAM via sysctl
    total = `sysctl -n hw.memsize`.to_i
    
    # Used RAM via vm_stat (Pages active + wired + compressed)
    # vm_stat output: "Pages free: 12345."
    vm_stat = `vm_stat`
    page_size = `pagesize`.to_i # souvent 4096 ou 16384 (M1)
    
    def get_vm_val(text, key)
      text.match(/#{key}:\s+(\d+)\./)&.captures&.first&.to_i || 0
    end
    
    pages_free = get_vm_val(vm_stat, "Pages free")
    pages_active = get_vm_val(vm_stat, "Pages active")
    pages_inactive = get_vm_val(vm_stat, "Pages inactive")
    pages_speculative = get_vm_val(vm_stat, "Pages speculative")
    pages_wired = get_vm_val(vm_stat, "Pages wired down")
    pages_compressed = get_vm_val(vm_stat, "Pages occupied by compressor")
    
    # "App Memory" = (Anonymous + Purgeable) but simpler approximation:
    # Used = (Active + Wired + Compressed) * PageSize
    # (Inactive is often considered "available" / file cache on macOS)
    
    used_pages = pages_active + pages_wired + pages_compressed
    used = used_pages * page_size
    
    percent = total > 0 ? ((used.to_f / total.to_f) * 100).round(1) : 0.0
    
    { total: total, used: used, percent: percent }
  else
    { total: 0, used: 0, percent: 0 }
  end
end

def get_cpu_temperature
  begin
    if is_linux?
      [ '/sys/class/thermal/thermal_zone0/temp', '/sys/devices/virtual/thermal/thermal_zone0/temp' ].each do |path|
        if File.exist?(path)
          raw = File.read(path).to_i
          return (raw > 150 ? raw / 1000.0 : raw).round(1)
        end
      end
    elsif is_mac?
      # Difficile sans gem externe (istats ou similar). On renvoie nil pour le moment pour éviter erreur.
      return nil
    end
  rescue; end
  nil
end

def get_uptime_seconds
    if is_linux? && File.exist?('/proc/uptime')
        File.read('/proc/uptime').split[0].to_i rescue 0
    elsif is_mac?
        # sysctl -n kern.boottime -> { sec = 1705678900, usec = ... }
        # output format: "{ sec = 1737380903, usec = 447036 } Thu Jan 20 14:48:23 2026"
        out = `sysctl -n kern.boottime`
        if out =~ /sec = (\d+)/
            boot_time = $1.to_i
            Time.now.to_i - boot_time
        else
            0
        end
    else
        0
    end
end

def get_local_ip
  ip = Socket.ip_address_list.detect { |addr| addr.ipv4? && !addr.ipv4_loopback? }&.ip_address
  ip || (is_mac? ? `ipconfig getifaddr en0`.strip : `hostname -I | awk '{print $1}'`.strip)
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
    if is_linux?
        # linux 'ps' args: -e (all), -o (format)
        sort_arg = sort == 'mem' ? '--sort=-%mem' : '--sort=-%cpu'
        output = `ps -eo pid,user,%cpu,%mem,comm #{sort_arg} | head -n #{limit + 1}`
        output.lines.drop(1).each do |line|
            parts = line.split
            next if parts.length < 5
            processes << { pid: parts[0], user: parts[1], cpu: parts[2].to_f, mem: parts[3].to_f, command: parts[4..].join(' ') }
        end
    elsif is_mac?
        # macOS ps ne supporte pas --sort. On fetch tout et on trie en Ruby.
        output = `ps -Ao pid,user,%cpu,%mem,comm`
        output.lines.drop(1).each do |line|
            parts = line.split
            next if parts.length < 5
            processes << { pid: parts[0], user: parts[1], cpu: parts[2].to_f, mem: parts[3].to_f, command: parts[4..].join(' ') }
        end
        
        # Tri Ruby
        if sort == 'mem'
            processes.sort_by! { |p| -p[:mem] }
        else
            processes.sort_by! { |p| -p[:cpu] }
        end
        processes = processes.first(limit)
    end
  rescue => e
    puts "Process Error: #{e.message}"
  end
  { processes: processes }.to_json
end

def get_disks_via_sys_filesystem
  d = []
  Sys::Filesystem.mounts.each { |m| 
    # Ignore pseudo-fs
    next if m.mount_type =~ /tmpfs|proc|devfs|sysfs|squashfs|autofs|devpts/
    begin
      s = Sys::Filesystem.stat(m.mount_point)
      t = s.blocks * s.block_size
      next if t < 10**9 
      d << { device: m.name, mountpoint: m.mount_point, total_bytes: t, used_bytes: t-(s.blocks_free*s.block_size) }
    rescue; end
  }
  d
end

def get_disks_via_df
  d = []
  begin
    if is_linux?
        # df -B1
        `df -B1 -x tmpfs -x devtmpfs -x squashfs`.lines.drop(1).each do |line|
          parts = line.split
          next if parts.length < 6
          total = parts[1].to_i
          used = parts[2].to_i
          mount = parts[5]
          next if total < 10**9 
          d << { device: parts[0], mountpoint: mount, total_bytes: total, used_bytes: used }
        end
    elsif is_mac?
        # df -k (kilobytes) sur mac. output: Filesystem 1024-blocks Used Available Capacity iused ifree %iused Mounted on
        `df -k`.lines.drop(1).each do |line|
           parts = line.split
           # Mac df output can be tricky if mount path has spaces, but usually last col.
           # Typically: /dev/disk3s1s1 484767224 23377720 376679584 6% 304560 3766795840 0% /System/Volumes/Data
           # parts: [0]=fs, [1]=blocks(1k), [2]=used(1k), [3]=avail(1k), [4]=cap, ... last=mount
           
           next if parts.length < 6
           total = parts[1].to_i * 1024
           used = parts[2].to_i * 1024
           mount = parts.last # Simplification (échoue si espace dans nom, mais acceptable pour MVP)
           
           next if total < 10**9
           d << { device: parts[0], mountpoint: mount, total_bytes: total, used_bytes: used }
        end
    end
  rescue; end
  d
end

get '/api/disks' do
  content_type :json
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

  begin
    if is_linux?
        # ip neigh
        `ip neigh`.each_line do |line|
            parts = line.split
            ip = parts[0]
            next unless ip =~ /^\d+\.\d+\.\d+\.\d+$/ 
            hostname = "Inconnu"
            state = parts.last
            next if state == 'FAILED'
            devices << { ip: ip, hostname: hostname, status: 'up', is_local: (ip == local_ip), source: 'arp' }
        end
    elsif is_mac?
        # arp -a
        # output: ? (192.168.1.1) at 0:11:22:33:44:55 on en0 ifscope [ethernet]
        `arp -a`.each_line do |line|
            if line =~ /\((\d+\.\d+\.\d+\.\d+)\) at ([a-fA-F0-9:]+)/
                ip = $1
                mac = $2
                hostname = line.split(' ').first
                hostname = "Inconnu" if hostname == "?"
                devices << { ip: ip, hostname: hostname, status: 'up', is_local: (ip == local_ip), source: 'arp' }
            end
        end
    end
    
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
    if is_linux? && File.exist?('/proc/net/dev')
        File.read('/proc/net/dev').lines.drop(2).each do |line|
          parts = line.split
          iface = parts[0].tr(':', '')
          next if iface == 'lo' 
          rx += parts[1].to_i
          tx += parts[9].to_i
        end
    elsif is_mac?
        # netstat -ib (bytes)
        # Name  Mtu   Network       Address            Ipkts Ierrs    Ibytes    Opkts Oerrs    Obytes  Coll
        # en0   1500  <Link#4>      ...                123   0        456       789   0        101     0
        # Attention: netstat -ib répète les lignes pour ipv4/ipv6. Faut éviter de double compter.
        # Astuce: filtrer sur "Link" pour avoir le total physique une seule fois par interface.
        `netstat -ib`.each_line do |line|
            parts = line.split
            next unless parts.length > 9
            iface = parts[0]
            # Colonnes variables si Address est présent ou non (Address est col 3 ou 4)
            # Mais netstat -ib aligne : Name Mtu Network Address Ipkts Ierrs Ibytes ...
            # Si <Link#...> est présent, c'est le compteur physique.
            # ex: en0 1500 <Link#4> 00:e0:... 12345 0 987654 ...
            next if iface =~ /^lo/ # skip loopback
            
            # Pour faire simple on cherche la ligne avec <Link...>
            if line =~ /<Link#/
                # Ibytes = col 6 (0-indexed), Obytes = col 9
                # parts: 0=Name, 1=Mtu, 2=Network, 3=Address, 4=Ipkts, 5=Ierrs, 6=Ibytes, 7=Opkts, 8=Oerrs, 9=Obytes
                rx += parts[6].to_i
                tx += parts[9].to_i
            end
        end
    end
  rescue; end
  { rx: rx, tx: tx }
end

def get_root_disk_usage
  result = { total: 0, used: 0, percent: 0 }
  begin
    if is_linux?
        output = `df -B1 /`.lines.last.split
        total = output[1].to_i
        used = output[2].to_i
        result = { total: total, used: used, percent: (total > 0 ? (used.to_f / total * 100).round(1) : 0) }
    elsif is_mac?
        output = `df -k /`.lines.last.split
        total = output[1].to_i * 1024
        used = output[2].to_i * 1024
        result = { total: total, used: used, percent: (total > 0 ? (used.to_f / total * 100).round(1) : 0) }
    end
  rescue; end
  result
end

# --- THREAD DE COLLECTE ---
Thread.new do
  system_info = get_system_info 
  
  loop do
    begin
      mem = get_memory_usage
      cpu = get_cpu_usage
      net = get_network_stats
      disk = get_root_disk_usage
      
      current_data = {
        timestamp: Time.now.to_i, 
        hostname: Socket.gethostname,
        platform: system_info[:platform], 
        os: system_info[:os],             
        cpu_cores: system_info[:cpu_cores],
        cpu_usage: cpu, 
        cpu_temp: get_cpu_temperature,
        memory_total_bytes: mem[:total], memory_used_bytes: mem[:used],
        memory_percent: mem[:percent],
        uptime_seconds: get_uptime_seconds,
        
        # New Data Feeds
        network_recv: net[:rx],
        network_sent: net[:tx],
        disk_total_bytes: disk[:total],
        disk_used_bytes: disk[:used],
        disk_percent: disk[:percent]
      }
      
      HISTORY << current_data
      HISTORY.shift if HISTORY.length > MAX_HISTORY
      
      if Time.now.to_i % 60 == 0
        File.open(LOG_FILE, 'a') { |f| f.puts "[#{Time.now}] INFO: CPU #{current_data[:cpu_usage]}% | Mem #{current_data[:memory_percent]}% | Net RX: #{current_data[:network_recv]}" }
      end
      
      sleep 1.5 
    rescue => e; puts "Loop Error: #{e.message}"; sleep 1; end
  end
end