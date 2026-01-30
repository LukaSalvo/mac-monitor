require_relative 'alert_manager'

module LogWatcher
  extend self

  def start(log_file)
    Thread.new do
      loop do
        if File.exist?(log_file)
          File.open(log_file) do |file|
            file.seek(0, IO::SEEK_END)
            loop do
              select([file])
              line = file.gets
              check_line(line) if line
            end
          end
        else
          sleep 1
        end
      rescue => e
        puts "LogWatcher Retry: #{e.message}"
        sleep 2
      end
    end
  end

  def check_line(line)
    require_relative 'ticket_store'
    
    if line =~ /FATAL|ERROR|CRITICAL/i
      TicketStore.upsert(
        'Critical Log Error',
        line.strip,
        'critical',
        fingerprint: 'log-critical'
      )
    elsif line =~ /WARN|WARNING/i
      TicketStore.upsert(
        'Log Warning',
        line.strip,
        'warning',
        fingerprint: 'log-warning'
      )
    end
  rescue => e
    puts "LogWatcher Error: #{e.message}"
  end
end
