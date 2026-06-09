require 'sinatra'
require 'json'
# require 'sys/filesystem'  # Commented out, using df fallback
require 'socket'
require 'rexml/document'
# require 'pony'
require 'rbconfig'
require 'etc'
require 'net/http'

require_relative 'lib/system_monitor'
require_relative 'lib/network_monitor'
require_relative 'lib/ticket_store'
require_relative 'lib/alert_manager'
require_relative 'lib/log_watcher'
require_relative 'lib/stress_tester'
require_relative 'lib/network_actions'

set :port, 3000
set :bind, '0.0.0.0'
set :public_folder, 'public'

TicketStore.init
LogWatcher.start(File.expand_path('app.log', __dir__))

HISTORY = []
MAX_HISTORY = 3600
LOG_FILE = File.expand_path('app.log', __dir__)
NMAP_PATH = "/usr/bin/nmap"




# Parse le corps JSON d'une requête, renvoie un hash vide en cas d'échec.
def parse_json_body
  body = request.body.read
  body.empty? ? {} : JSON.parse(body)
rescue JSON::ParserError
  {}
end

# --- AJOUT AU DÉBUT DU FICHIER app.rb ---

# Récupère la version locale via Git
def get_local_version
  # On force un fetch des tags silencieux avant de demander la version
  `git fetch --tags > /dev/null 2>&1` 
  version = `git describe --tags --abbrev=0 2>/dev/null`.strip
  version.empty? ? "v1.0.0" : version
end

# Vérifie la dernière version sur GitHub
def check_github_version
  repo = "LukaSalvo/mac-monitor" 
  uri = URI("https://api.github.com/repos/#{repo}/tags")
  
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  request = Net::HTTP::Get.new(uri)
  request['User-Agent'] = 'Ruby-Version-Checker'
  
  response = http.request(request)
  
  # Si l'API renvoie autre chose que 200 (ex: 404), on arrête
  return nil unless response.code == '200'
  
  tags = JSON.parse(response.body)
  tags.empty? ? nil : tags[0]['name']
rescue
  nil
end

# Route API pour le Frontend
get '/api/check_update' do
  content_type :json
  local = get_local_version
  remote = check_github_version
  
  {
    local: local,
    remote: remote,
    update_available: (remote && remote != local)
  }.to_json
end


get '/' do
  send_file File.join(settings.public_folder, 'index.html')
end

get '/api/tickets' do
  content_type :json
  TicketStore.all.to_json
end

post '/api/tickets/:id/close' do
  content_type :json
  ticket = TicketStore.update_status(params[:id], 'closed')
  if ticket
    { success: true, ticket: ticket }.to_json
  else
    status 404
    { success: false, error: 'Ticket not found' }.to_json
  end
end


get '/api/system' do
  content_type :json
  HISTORY.to_json
end

require_relative 'lib/dependency_manager'

# Stress Test Endpoints
post '/api/stress-test/start' do
  content_type :json
  StressTester.start.to_json
end

post '/api/stress-test/stop' do
  content_type :json
  StressTester.stop.to_json
end

get '/api/stress-test/status' do
  content_type :json
  StressTester.status.to_json
end

get '/api/updates' do
  content_type :json
  DependencyManager.check_updates.to_json
end

post '/api/updates/gems' do
  content_type :json
  success = DependencyManager.update_gems
  { success: success }.to_json
end

get '/api/processes' do
  content_type :json
  sort = params[:sort] || 'cpu'
  limit = (params[:limit] || 20).to_i
  { processes: SystemMonitor.get_processes(sort, limit) }.to_json
end

delete '/api/processes/:pid' do
  content_type :json
  pid = params[:pid].to_i
  begin
    Process.kill('TERM', pid)
    { success: true, message: "Signal TERM envoyé au PID #{pid}" }.to_json
  rescue Errno::ESRCH
    status 404
    { success: false, error: "Processus #{pid} introuvable" }.to_json
  rescue Errno::EPERM
    status 403
    { success: false, error: "Permission refusée pour le PID #{pid}" }.to_json
  end
end

get '/api/disks' do
  content_type :json
  { disks: SystemMonitor.get_disks }.to_json
end

get '/api/network/scan' do
  content_type :json
  { devices: NetworkMonitor.scan_network(SystemMonitor.get_local_ip, NMAP_PATH), local_ip: SystemMonitor.get_local_ip }.to_json
end

# Détails des interfaces réseau (consommé par la page Réseau).
get '/api/network' do
  content_type :json
  NetworkMonitor.get_interfaces.to_json
end

# Ping d'un appareil (latence en ms).
get '/api/network/ping/:ip' do
  content_type :json
  latency = NetworkMonitor.ping(params[:ip])
  { ip: params[:ip], reachable: !latency.nil?, latency_ms: latency }.to_json
end

# Wake-on-LAN : allume un appareil via son adresse MAC.
post '/api/network/wake' do
  content_type :json
  data = parse_json_body
  mac = data['mac'] || params['mac']
  result = NetworkActions.wake_on_lan(mac.to_s)
  AlertManager.trigger("Wake-on-LAN", result[:message], result[:success] ? 'info' : 'warning') rescue nil
  status 400 unless result[:success]
  result.to_json
end

# Arrêt distant d'un appareil du réseau (SSH pour Linux/macOS, SMB pour Windows).
post '/api/network/shutdown' do
  content_type :json
  data = parse_json_body
  ip = data['ip'] || params['ip']
  result = NetworkActions.shutdown_device(ip.to_s,
    os: data['os'],
    user: data['user'],
    password: data['password'],
    reboot: data['reboot'])
  AlertManager.trigger("Arrêt distant", "#{ip} : #{result[:message]}", result[:success] ? 'info' : 'warning') rescue nil
  status 400 unless result[:success]
  result.to_json
end

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

Thread.new do
  system_info = SystemMonitor.get_system_info
  
  loop do
    begin
      mem = SystemMonitor.get_memory_usage
      cpu = SystemMonitor.get_cpu_usage
      net = NetworkMonitor.get_network_stats
      disk = SystemMonitor.get_root_disk_usage
      
      current_data = {
        timestamp: Time.now.to_i, 
        hostname: Socket.gethostname,
        platform: system_info[:platform],
        os: system_info[:os],
        cpu_cores: system_info[:cpu_cores],
        cpu_usage: cpu, 
        cpu_temp: SystemMonitor.get_cpu_temperature,
        memory_total_bytes: mem[:total], memory_used_bytes: mem[:used],
        memory_percent: mem[:percent],
        uptime_seconds: SystemMonitor.get_uptime_seconds,
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
    rescue => e
      sleep 1
    end
  end
end