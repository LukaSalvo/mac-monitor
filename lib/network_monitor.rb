module NetworkMonitor
  extend self

  def scan_network(local_ip, nmap_path = "/usr/bin/nmap")
    devices = []

    if File.executable?(nmap_path)
      begin
        subnet = local_ip.split('.')[0..2].join('.') + '.0/24'
        xml_output = `sudo #{nmap_path} -sn -oX - #{subnet} 2>/dev/null`
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
      rescue; end
    end

    begin
      if SystemMonitor.is_linux?
        `ip neigh`.each_line do |line|
          parts = line.split
          ip = parts[0]
          next unless ip =~ /^\d+\.\d+\.\d+\.\d+$/
          hostname = "Inconnu"
          state = parts.last
          next if state == 'FAILED'
          devices << { ip: ip, hostname: hostname, status: 'up', is_local: (ip == local_ip), source: 'arp' }
        end
      elsif SystemMonitor.is_mac?
        `arp -a`.each_line do |line|
          if line =~ /\((\d+\.\d+\.\d+\.\d+)\) at ([a-fA-F0-9:]+)/
            ip = $1
            devices << { ip: ip, hostname: "Inconnu", status: 'up', is_local: (ip == local_ip), source: 'arp' }
          end
        end
      end

      unless devices.any? { |d| d[:is_local] }
        devices << { ip: local_ip, hostname: Socket.gethostname, status: 'up', is_local: true, source: 'local' }
      end
    rescue; end

    devices
  end

  def get_network_stats
    rx = 0
    tx = 0
    begin
      if SystemMonitor.is_linux? && File.exist?('/proc/net/dev')
        File.read('/proc/net/dev').lines.drop(2).each do |line|
          parts = line.split
          iface = parts[0].tr(':', '')
          next if iface == 'lo'
          rx += parts[1].to_i
          tx += parts[9].to_i
        end
      elsif SystemMonitor.is_mac?
        `netstat -ib`.each_line do |line|
          parts = line.split
          next unless parts.length > 9
          iface = parts[0]
          next if iface =~ /^lo/
          if line =~ /<Link#/
            rx += parts[6].to_i
            tx += parts[9].to_i
          end
        end
      end
    rescue; end
    { rx: rx, tx: tx }
  end
end
