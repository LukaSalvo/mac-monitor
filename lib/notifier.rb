module Notifier
  extend self

  def send_discord(title, message, color = 16711680)
    # Notifications disabled by user request.
    # Just logging to stdout for debugging purposes.
    puts "[NOTIFICATION] #{title}: #{message}"
    true
  end
end
