require_relative 'ticket_store'
require_relative 'notifier'

module AlertManager
  extend self

  def trigger(title, message, level = 'warning')
    return if recent_duplicate?(title)

    ticket = TicketStore.create(title, message, level)
    
    if level == 'critical'
      notify_admin(title, message)
    end
    
    ticket
  end

  def notify_admin(title, message)
    Notifier.send_discord(title, message)
  end

  # Prevent spamming same alert (simple in-memory cache)
  @recent_alerts = {}

  def recent_duplicate?(title)
    last_time = @recent_alerts[title]
    if last_time && (Time.now.to_i - last_time < 300) # 5 min cooldown
      return true
    end
    @recent_alerts[title] = Time.now.to_i
    false
  end
end
