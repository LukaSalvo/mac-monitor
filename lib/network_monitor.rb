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
            mac_el = host.elements["address[@addrtype='mac']"]
            mac = mac_el&.attributes&.[]('addr')
            vendor = mac_el&.attributes&.[]('vendor')
            hostname_el = host.elements["hostnames/hostname"]
            hostname = hostname_el ? hostname_el.attributes['name'] : "Inconnu"
            devices << {
              ip: ip,
              hostname: hostname,
              mac: mac,
              vendor: vendor,
              status: 'up',
              is_local: (ip == local_ip),
              source: 'nmap'
            }
          end
          return enrich_devices(devices) unless devices.empty?
        end
      rescue; end
    end

    begin
      if SystemMonitor.is_linux?
        `ip neigh`.each_line do |line|
          parts = line.split
          ip = parts[0]
          next unless ip =~ /^\d+\.\d+\.\d+\.\d+$/
          state = parts.last
          next if state == 'FAILED'
          mac = parts.include?('lladdr') ? parts[parts.index('lladdr') + 1] : nil
          devices << { ip: ip, hostname: "Inconnu", mac: mac, vendor: vendor_for(mac), status: 'up', is_local: (ip == local_ip), source: 'arp' }
        end
      elsif SystemMonitor.is_mac?
        `arp -a`.each_line do |line|
          if line =~ /\((\d+\.\d+\.\d+\.\d+)\) at ([a-fA-F0-9:]+)/
            ip = $1
            mac = normalize_mac($2)
            hostname = line[/^([^\s]+)\s+\(/, 1]
            hostname = "Inconnu" if hostname.nil? || hostname == '?'
            devices << { ip: ip, hostname: hostname, mac: mac, vendor: vendor_for(mac), status: 'up', is_local: (ip == local_ip), source: 'arp' }
          end
        end
      end

      unless devices.any? { |d| d[:is_local] }
        devices << { ip: local_ip, hostname: Socket.gethostname, mac: local_mac, vendor: 'Cette machine', status: 'up', is_local: true, source: 'local' }
      end
    rescue; end

    enrich_devices(devices)
  end

  # Écarte les adresses non-hôtes (broadcast, multicast, réseau).
  def real_host?(ip)
    return false unless ip =~ /^\d+\.\d+\.\d+\.\d+$/
    octets = ip.split('.').map(&:to_i)
    return false if octets[0] >= 224          # multicast (224-239) + réservé (240+)
    return false if octets[3] == 255          # broadcast
    return false if octets[3].zero?           # adresse réseau
    true
  end

  # Ajoute la latence (ping) et le type devine à chaque appareil découvert.
  def enrich_devices(devices)
    devices = devices.reject { |d| !real_host?(d[:ip]) }
                     .uniq { |d| d[:ip] }
    gateway = get_gateway
    devices.each do |dev|
      dev[:latency_ms] = ping(dev[:ip]) unless dev[:is_local]
      info = classify_device(dev, gateway)
      dev[:device_type] = info[:type]
      dev[:device_label] = info[:label]
      dev[:device_icon] = info[:icon]
    end
    devices
  end

  # IP de la passerelle par défaut (= routeur, en général).
  def get_gateway
    if SystemMonitor.is_mac?
      `route -n get default 2>/dev/null`[/gateway:\s*([\d.]+)/, 1]
    elsif SystemMonitor.is_linux?
      `ip route 2>/dev/null`[/default via\s+([\d.]+)/, 1]
    end
  rescue
    nil
  end

  # Devine le type d'appareil à partir du vendor, du hostname, de la MAC et de la passerelle.
  # Renvoie { type:, label:, icon: } (icon = nom Font Awesome).
  def classify_device(dev, gateway = nil)
    host = dev[:hostname].to_s.downcase
    vendor = dev[:vendor].to_s.downcase
    ip = dev[:ip].to_s
    blob = "#{host} #{vendor}"

    # 1. Cette machine
    return type_info(:computer) if dev[:is_local]

    # 2. Passerelle = routeur
    return type_info(:router) if !gateway.nil? && ip == gateway
    return type_info(:router) if blob =~ /router|gateway|livebox|freebox|bbox|sfrbox|fritz|netgear|tp-?link|asus|dlink|d-link|orange|huawei.*hg|gateway|passerelle|\.1$/
    return type_info(:router) if ip.end_with?('.1') || ip.end_with?('.254')

    # 3. Téléphones
    return type_info(:phone) if blob =~ /iphone|android|pixel|galaxy.*s\d|sm-[gn]|oneplus|xiaomi|redmi|oppo|vivo|huawei.*p\d|nokia|smartphone|phone/

    # 4. Tablettes
    return type_info(:tablet) if blob =~ /ipad|tablet|tab-?[as]\d|sm-t\d|surface/

    # 5. TV / box multimédia
    return type_info(:tv) if blob =~ /tv|appletv|apple-?tv|chromecast|roku|firetv|fire-?tv|shield|bravia|samsung.*tv|lg.*tv|webos|android.*tv|kodi|plex/

    # 6. Consoles de jeu
    return type_info(:console) if blob =~ /playstation|ps[345]|xbox|nintendo|switch/

    # 7. Imprimantes
    return type_info(:printer) if blob =~ /printer|imprimante|hp.*print|epson|canon|brother|lexmark|officejet|laserjet|deskjet/

    # 8. NAS / serveurs de stockage
    return type_info(:nas) if blob =~ /nas|synology|qnap|diskstation|drobo|truenas|freenas|wdmycloud/

    # 9. Objets connectés / domotique
    return type_info(:iot) if blob =~ /esp|esp32|esp8266|espressif|sonoff|tasmota|shelly|nest|hue|tradfri|tuya|smartlife|alexa|echo|amazon|google-?home|nest-?mini|sonos|ring|netatmo|tplink.*plug|kasa|thermostat|camera|cam-|ipcam/

    # 10. Raspberry Pi / mini-PC
    return type_info(:raspberry) if blob =~ /raspberry|raspberrypi|raspberry pi|libreelec|octopi/

    # 11. Ordinateurs (vendors PC / Mac connus)
    return type_info(:computer) if blob =~ /macbook|imac|mac-?mini|mac-?pro|desktop|laptop|pc-|windows|win-|dell|lenovo|thinkpad|hp-?elite|hp-?pavilion|asus.*book|acer|msi|surface-?laptop|intel|micro-?star|gigabyte|asrock/

    # 12. Apple générique (souvent iPhone/iPad/Mac) -> appareil Apple
    return type_info(:apple) if vendor =~ /apple/

    # 13. Inconnu
    type_info(:unknown)
  end

  DEVICE_TYPES = {
    router:    { label: 'Routeur',        icon: 'wifi' },
    phone:     { label: 'Téléphone',      icon: 'mobile-screen-button' },
    tablet:    { label: 'Tablette',       icon: 'tablet-screen-button' },
    tv:        { label: 'TV / Box',       icon: 'tv' },
    console:   { label: 'Console de jeu', icon: 'gamepad' },
    printer:   { label: 'Imprimante',     icon: 'print' },
    nas:       { label: 'NAS / Stockage', icon: 'database' },
    iot:       { label: 'Objet connecté', icon: 'house-signal' },
    raspberry: { label: 'Raspberry / Mini-PC', icon: 'microchip' },
    computer:  { label: 'Ordinateur',     icon: 'desktop' },
    apple:     { label: 'Appareil Apple', icon: 'apple' },
    unknown:   { label: 'Inconnu',        icon: 'circle-question' }
  }.freeze

  def type_info(key)
    meta = DEVICE_TYPES[key] || DEVICE_TYPES[:unknown]
    { type: key.to_s, label: meta[:label], icon: meta[:icon] }
  end

  # Ping ICMP unique, renvoie la latence en ms ou nil si injoignable.
  def ping(ip)
    return nil unless ip =~ /^\d+\.\d+\.\d+\.\d+$/
    flag = SystemMonitor.is_mac? ? '-t 1' : '-W 1'
    out = `ping -c 1 #{flag} #{ip} 2>/dev/null`
    if out =~ /time[=<]([\d.]+)\s*ms/
      $1.to_f.round(1)
    else
      nil
    end
  rescue
    nil
  end

  # MAC de la machine locale (pour info / WoL).
  def local_mac
    if SystemMonitor.is_mac?
      iface = `route get default 2>/dev/null`[/interface:\s*(\w+)/, 1] || 'en0'
      `ifconfig #{iface} 2>/dev/null`[/ether\s+([a-fA-F0-9:]+)/, 1]
    elsif SystemMonitor.is_linux?
      Dir.glob('/sys/class/net/*/address').map { |f| File.read(f).strip }.find { |m| m != '00:00:00:00:00:00' }
    end
  rescue
    nil
  end

  # Liste les interfaces réseau et leurs compteurs (corrige /api/network).
  def get_interfaces
    interfaces = []
    begin
      if SystemMonitor.is_linux? && File.exist?('/proc/net/dev')
        File.read('/proc/net/dev').lines.drop(2).each do |line|
          parts = line.split
          iface = parts[0].tr(':', '')
          next if iface == 'lo'
          interfaces << { interface: iface, bytes_recv: parts[1].to_i, bytes_sent: parts[9].to_i }
        end
      elsif SystemMonitor.is_mac?
        `netstat -ib`.each_line do |line|
          parts = line.split
          next unless parts.length > 9
          iface = parts[0]
          next if iface =~ /^lo/
          if line =~ /<Link#/
            interfaces << { interface: iface, bytes_recv: parts[6].to_i, bytes_sent: parts[9].to_i }
          end
        end
      end
    rescue; end
    interfaces
  end

  def normalize_mac(mac)
    return nil if mac.nil?
    mac.split(':').map { |b| b.rjust(2, '0') }.join(':').downcase
  end

  # Best-effort vendor lookup via le préfixe OUI connu (table embarquée minimale).
  def vendor_for(mac)
    return nil if mac.nil?
    prefix = mac.tr(':-', '').downcase[0, 6]
    OUI_PREFIXES[prefix]
  end

  # Table OUI embarquée (préfixes des 3 premiers octets, sans séparateur, minuscule).
  # Best-effort pour le repli ARP ; nmap fournit le vendor complet quand exécuté en root.
  OUI_PREFIXES = {
    # Apple
    'f0d1a9' => 'Apple', 'a4c361' => 'Apple', '3c0754' => 'Apple', '88665a' => 'Apple',
    '001b63' => 'Apple', 'ac87a3' => 'Apple', 'f0dbe2' => 'Apple', 'd49a20' => 'Apple',
    '040cce' => 'Apple', '7cd1c3' => 'Apple', 'bc926b' => 'Apple', '90b21f' => 'Apple',
    # Samsung
    'd83134' => 'Samsung', '5cf6dc' => 'Samsung', '082599' => 'Samsung', '8425db' => 'Samsung',
    '34be00' => 'Samsung', 'e8508b' => 'Samsung',
    # Google / Nest
    '001a11' => 'Google', 'f4f5d8' => 'Google', '3c5ab4' => 'Google', '6466b3' => 'Google',
    'd8c562' => 'Nest', '18b430' => 'Nest',
    # Amazon (Echo / Fire)
    'fc65de' => 'Amazon', '44650d' => 'Amazon', 'a002dc' => 'Amazon', '68543d' => 'Amazon',
    # Espressif (ESP32/ESP8266 → IoT)
    '240ac4' => 'Espressif', '3c71bf' => 'Espressif', '8caab5' => 'Espressif', 'a4cf12' => 'Espressif',
    'ecfabc' => 'Espressif', '7c9ebd' => 'Espressif',
    # Raspberry Pi
    'b827eb' => 'Raspberry Pi', 'dca632' => 'Raspberry Pi', 'e45f01' => 'Raspberry Pi', '28cdc1' => 'Raspberry Pi',
    # Microsoft / Intel
    '0050f2' => 'Microsoft', '001dd8' => 'Microsoft', '7c1e52' => 'Microsoft', '001517' => 'Intel',
    '3c970e' => 'Intel',
    # Routeurs / réseau
    '001fc6' => 'ASUSTek router', '305a3a' => 'ASUSTek router', '00248c' => 'ASUSTek router',
    'fcfbfb' => 'Cisco router', '0021b7' => 'Netgear router', '20e52a' => 'Netgear router',
    'd8074a' => 'TP-Link router', '50c7bf' => 'TP-Link router', 'a42bb0' => 'TP-Link router',
    # NAS
    '001132' => 'Synology NAS', '24050f' => 'QNAP NAS',
    # Sony (PlayStation)
    'fc0fe6' => 'Sony PlayStation', 'd44b5e' => 'Sony PlayStation', '709e29' => 'Sony PlayStation',
    # Domotique
    '001788' => 'Philips Hue', 'ecb5fa' => 'Philips Hue',
    '70ee50' => 'Netatmo', '5c0272' => 'Sonos', '949f3e' => 'Sonos', '347e5c' => 'Sonos',
    # PC
    'cc19a8' => 'HP', '3c52a1' => 'HP', '70106f' => 'HP', '001e0b' => 'HP',
    '60a44c' => 'Lenovo', '54ee75' => 'Lenovo', 'd0577b' => 'Dell', 'b083fe' => 'Dell',
    # Xiaomi / Huawei
    '286c07' => 'Xiaomi', '64cc2e' => 'Xiaomi', '00e0fc' => 'Huawei', '48ad08' => 'Huawei'
  }.freeze

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
