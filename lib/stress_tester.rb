module StressTester
  extend self

  @stress_thread = nil
  @running = false

  def running?
    @running
  end

  def start
    return { success: false, message: "Stress test already running" } if @running

    @running = true
    @stress_thread = Thread.new do
      begin
        puts "[STRESS TEST] Starting stress test..."
        
        loop do
          break unless @running
          
          # CPU Stress: Calculs intensifs
          cpu_stress
          
          # Memory Stress: Allocation temporaire
          memory_stress
          
          # Log Stress: Génération d'erreurs
          log_stress
          
          sleep 2  # Pause entre les cycles
        end
        
        puts "[STRESS TEST] Stopped"
      rescue => e
        puts "[STRESS TEST ERROR] #{e.message}"
        @running = false
      end
    end

    { success: true, message: "Stress test started" }
  end

  def stop
    return { success: false, message: "No stress test running" } unless @running

    @running = false
    @stress_thread.join(5) if @stress_thread  # Attendre max 5 secondes
    @stress_thread = nil

    # Fermer automatiquement les tickets liés au stress test
    close_stress_test_tickets

    { success: true, message: "Stress test stopped" }
  end

  def status
    {
      running: @running,
      message: @running ? "Stress test in progress" : "Stress test idle"
    }
  end

  private

  # Stress CPU: Calculs de nombres premiers
  def cpu_stress
    limit = 50000
    primes = []
    (2..limit).each do |num|
      is_prime = true
      (2..Math.sqrt(num).to_i).each do |i|
        if num % i == 0
          is_prime = false
          break
        end
      end
      primes << num if is_prime
      break if primes.length > 100  # Limiter pour ne pas bloquer
    end
  end

  # Stress Memory: Allocation temporaire de tableaux
  def memory_stress
    # Allouer ~100MB temporairement
    temp_data = Array.new(10_000_000) { rand(1000) }
    temp_data.sample(100)  # Utiliser un peu les données
    temp_data = nil  # Libérer immédiatement
    GC.start  # Forcer le garbage collector
  end

  # Stress Logs:  # Génère des logs d'erreur pour tester le système de tickets
  def generate_error_logs
    log_file = File.expand_path('../app.log', __dir__)
    File.open(log_file, 'a') do |f|
      f.puts "[#{Time.now}] ERROR: Stress test - High CPU usage detected"
      f.puts "[#{Time.now}] FATAL: Stress test - Memory threshold exceeded"
    end
  end

  # Ferme automatiquement les tickets créés par le stress test
  def close_stress_test_tickets
    require_relative 'ticket_store'
    
    # Fermer tous les tickets contenant "Stress test" dans le titre
    tickets = TicketStore.all
    stress_tickets = tickets.select { |t| t[:status] == 'open' && t[:title]&.include?('Stress test') }
    
    stress_tickets.each do |ticket|
      TicketStore.update_status(ticket[:id], 'closed')
      puts "[STRESS TEST] Auto-closed ticket: #{ticket[:title]}"
    end
    
    puts "[STRESS TEST] Closed #{stress_tickets.length} ticket(s)" if stress_tickets.any?
  end
end
