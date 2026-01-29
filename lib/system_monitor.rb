module SystemMonitor
  extend self

  def is_mac?
    RbConfig::CONFIG['host_os'] =~ /darwin/
  end

  def is_linux?
    RbConfig::CONFIG['host_os'] =~ /linux/
  end

  def get_system_info
    {
      os: RbConfig::CONFIG['host_os'],
      platform: RbConfig::CONFIG['host_cpu'],
      cpu_cores: Etc.nprocessors
    }
  end

  def get_cpu_usage
    if is_linux? && File.exist?('/proc/stat')
      cpu1 = File.read('/proc/stat').lines.first.split.map(&:to_i)
      sleep 0.5
      cpu2 = File.read('/proc/stat').lines.first.split.map(&:to_i)

      idle1 = cpu1[4] + cpu1[5]
      total1 = cpu1[1..].sum

      idle2 = cpu2[4] + cpu2[5]
      total2 = cpu2[1..].sum

      diff_idle = idle2 - idle1
      diff_total = total2 - total1

      return 0.0 if diff_total == 0
      ((1.0 - diff_idle.to_f / diff_total.to_f) * 100).round(1)
    elsif is_mac?
      begin
        output = `top -l 1 -n 0 | grep "CPU usage"`
        if output =~ /([0-9.]+)% user,\s+([0-9.]+)% sys/
          ($1.to_f + $2.to_f).round(1)
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
        meminfo[parts[0].strip] = parts[1].strip.to_i * 1024
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
      total = `sysctl -n hw.memsize`.to_i
      vm_stat = `vm_stat`
      page_size = `pagesize`.to_i

      def get_vm_val(text, key)
        text.match(/#{key}:\s+(\d+)\./)&.captures&.first&.to_i || 0
      end

      active = get_vm_val(vm_stat, "Pages active")
      wired = get_vm_val(vm_stat, "Pages wired down")
      compressed = get_vm_val(vm_stat, "Pages occupied by compressor")

      used = (active + wired + compressed) * page_size
      percent = total > 0 ? ((used.to_f / total.to_f) * 100).round(1) : 0.0

      { total: total, used: used, percent: percent }
    else
      { total: 0, used: 0, percent: 0 }
    end
  end

  def get_cpu_temperature
    if is_linux?
      ['/sys/class/thermal/thermal_zone0/temp', '/sys/devices/virtual/thermal/thermal_zone0/temp'].each do |path|
        if File.exist?(path)
          raw = File.read(path).to_i
          return (raw > 150 ? raw / 1000.0 : raw).round(1)
        end
      end
    end
    nil
  rescue
    nil
  end

  def get_uptime_seconds
    if is_linux? && File.exist?('/proc/uptime')
      File.read('/proc/uptime').split[0].to_i rescue 0
    elsif is_mac?
      out = `sysctl -n kern.boottime`
      if out =~ /sec = (\d+)/
        Time.now.to_i - $1.to_i
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

  def check_updates
    results = { system_updates: [], gem_updates: [], os: "Unknown" }
    host_os = RbConfig::CONFIG['host_os']

    if host_os =~ /linux/
      results[:os] = "Linux"
      output = `apt list --upgradable 2>/dev/null | grep /`
      results[:system_updates] = output.split("\n").reject(&:empty?).map { |l| l.split("/")[0] }
    elsif host_os =~ /darwin/
      results[:os] = "macOS"
      output = `brew outdated --short 2>/dev/null`
      results[:system_updates] = output.split("\n").reject(&:empty?)
    end

    gem_output = `bundle outdated --parseable 2>/dev/null`
    results[:gem_updates] = gem_output.split("\n").map { |l| l.split(" ")[1] }.compact
    results
  end

  def get_processes(sort, limit)
    processes = []
    begin
      if is_linux?
        sort_arg = sort == 'mem' ? '--sort=-%mem' : '--sort=-%cpu'
        output = `ps -eo pid,user,%cpu,%mem,comm #{sort_arg} | head -n #{limit + 1}`
        output.lines.drop(1).each do |line|
          parts = line.split
          next if parts.length < 5
          processes << { pid: parts[0], user: parts[1], cpu: parts[2].to_f, mem: parts[3].to_f, command: parts[4..].join(' ') }
        end
      elsif is_mac?
        output = `ps -Ao pid,user,%cpu,%mem,comm`
        output.lines.drop(1).each do |line|
          parts = line.split
          next if parts.length < 5
          processes << { pid: parts[0], user: parts[1], cpu: parts[2].to_f, mem: parts[3].to_f, command: parts[4..].join(' ') }
        end

        if sort == 'mem'
          processes.sort_by! { |p| -p[:mem] }
        else
          processes.sort_by! { |p| -p[:cpu] }
        end
        processes = processes.first(limit)
      end
    rescue => e
      puts e.message
    end
    processes
  end

def get_disks
  d = []

  # Essaye sys-filesystem si dispo, sinon fallback df (évite NameError)
  begin
    require 'sys/filesystem'
    Sys::Filesystem.mounts.each do |m|
      next if m.mount_type =~ /tmpfs|proc|devfs|sysfs|squashfs|autofs|devpts/
      begin
        s = Sys::Filesystem.stat(m.mount_point)
        t = s.blocks * s.block_size
        next if t < 10**9
        d << {
          device: m.name,
          mountpoint: m.mount_point,
          total_bytes: t,
          used_bytes: t - (s.blocks_free * s.block_size)
        }
      rescue
      end
    end
  rescue LoadError, NameError
    # sys-filesystem absent -> on laisse d vide, et on passera au fallback df
  end

  if d.empty?
    begin
      if is_linux?
        `df -B1 -x tmpfs -x devtmpfs -x squashfs`.lines.drop(1).each do |line|
          parts = line.split
          next if parts.length < 6
          total = parts[1].to_i
          used  = parts[2].to_i
          mount = parts[5]
          next if total < 10**9
          d << { device: parts[0], mountpoint: mount, total_bytes: total, used_bytes: used }
        end
      elsif is_mac?
        `df -k`.lines.drop(1).each do |line|
          parts = line.split
          next if parts.length < 6
          total = parts[1].to_i * 1024
          used  = parts[2].to_i * 1024
          mount = parts.last
          next if total < 10**9
          d << { device: parts[0], mountpoint: mount, total_bytes: total, used_bytes: used }
        end
      end
    rescue
    end
  end

  d
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
end
