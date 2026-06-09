require 'socket'
require 'shellwords'

# Actions sur les appareils du réseau local :
#  - Wake-on-LAN (allumage à distance via paquet magique)
#  - Arrêt distant (Linux/macOS via SSH, Windows via SMB net rpc)
#
# L'arrêt distant nécessite des accès sur la machine cible :
#  - Linux/macOS : clé SSH autorisée (ou sshpass installé pour un mot de passe),
#    et un sudo sans mot de passe pour `shutdown`.
#  - Windows    : Samba (`net`) installé localement et compte administrateur distant.
module NetworkActions
  extend self

  # Envoie un paquet magique Wake-on-LAN à l'adresse MAC fournie.
  # Le broadcast est envoyé sur le port UDP 9 (et 7 en secours).
  def wake_on_lan(mac, broadcast = '255.255.255.255')
    clean = mac.to_s.gsub(/[^0-9a-fA-F]/, '')
    return { success: false, message: "Adresse MAC invalide" } unless clean.length == 12

    bytes = clean.scan(/../).map { |h| h.to_i(16) }
    magic = ([0xff] * 6 + bytes * 16).pack('C*')

    [9, 7].each do |port|
      sock = UDPSocket.new
      sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_BROADCAST, true)
      sock.send(magic, 0, broadcast, port)
      sock.close
    end

    { success: true, message: "Paquet Wake-on-LAN envoyé à #{format_mac(clean)}" }
  rescue => e
    { success: false, message: "Échec WoL : #{e.message}" }
  end

  # Arrête (ou redémarre) un appareil distant.
  # opts:
  #   :os       => 'linux' | 'mac' | 'windows'  (défaut: 'linux')
  #   :user     => identifiant
  #   :password => mot de passe (optionnel ; SSH par clé sinon)
  #   :reboot   => true pour redémarrer au lieu d'éteindre
  def shutdown_device(ip, opts = {})
    return { success: false, message: "Adresse IP invalide" } unless valid_ip?(ip)

    os = (opts[:os] || 'linux').to_s.downcase
    user = opts[:user].to_s.strip
    password = opts[:password].to_s
    reboot = !!opts[:reboot]

    case os
    when 'windows'
      shutdown_windows(ip, user, password, reboot)
    else
      shutdown_ssh(ip, user, password, reboot, os)
    end
  end

  private

  def shutdown_ssh(ip, user, password, reboot, os)
    return { success: false, message: "Utilisateur SSH requis" } if user.empty?

    remote_cmd = if os == 'mac'
                   reboot ? 'sudo shutdown -r now' : 'sudo shutdown -h now'
                 else
                   reboot ? 'sudo shutdown -r now' : 'sudo shutdown -h now'
                 end

    target = "#{Shellwords.escape(user)}@#{ip}"
    ssh_opts = "-o ConnectTimeout=5 -o StrictHostKeyChecking=no"

    cmd =
      if password.empty?
        # Authentification par clé SSH (BatchMode = pas de prompt interactif).
        "ssh -o BatchMode=yes #{ssh_opts} #{target} #{Shellwords.escape(remote_cmd)} 2>&1"
      elsif sshpass_available?
        "sshpass -p #{Shellwords.escape(password)} ssh #{ssh_opts} #{target} #{Shellwords.escape(remote_cmd)} 2>&1"
      else
        return { success: false, message: "sshpass introuvable : installez-le ou utilisez une clé SSH." }
      end

    out = `#{cmd}`
    status = $?.exitstatus

    if status == 0 || out.strip.empty? || out =~ /closed by remote host|Connection to .* closed/i
      { success: true, message: "Commande d'arrêt envoyée à #{ip}" }
    else
      { success: false, message: "Échec SSH (#{status}) : #{out.strip[0, 200]}" }
    end
  rescue => e
    { success: false, message: "Erreur : #{e.message}" }
  end

  def shutdown_windows(ip, user, password, reboot)
    return { success: false, message: "Utilisateur Windows requis" } if user.empty?
    unless command_exists?('net')
      return { success: false, message: "Outil Samba `net` introuvable côté serveur." }
    end

    creds = password.empty? ? Shellwords.escape(user) : "#{Shellwords.escape(user)}%#{Shellwords.escape(password)}"
    flag = reboot ? '-r' : ''
    cmd = "net rpc shutdown #{flag} -f -t 5 -C #{Shellwords.escape('Arret demande par Moniteur Systeme')} -I #{ip} -U #{creds} 2>&1"

    out = `#{cmd}`
    if $?.exitstatus == 0
      { success: true, message: "Commande d'arrêt Windows envoyée à #{ip}" }
    else
      { success: false, message: "Échec : #{out.strip[0, 200]}" }
    end
  rescue => e
    { success: false, message: "Erreur : #{e.message}" }
  end

  def valid_ip?(ip)
    ip.to_s =~ /\A\d{1,3}(\.\d{1,3}){3}\z/ && ip.split('.').all? { |o| o.to_i.between?(0, 255) }
  end

  def format_mac(clean)
    clean.scan(/../).join(':')
  end

  def sshpass_available?
    command_exists?('sshpass')
  end

  def command_exists?(name)
    system("command -v #{Shellwords.escape(name)} > /dev/null 2>&1")
  end
end
