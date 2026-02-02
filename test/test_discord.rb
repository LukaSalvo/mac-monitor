#!/usr/bin/env ruby
# Test Discord webhook

require 'bundler/setup'
require_relative '../lib/notifier'

puts "=== Test Discord Webhook ==="
puts ""

test_ticket = {
  id: "test-discord-#{Time.now.to_i}",
  first_seen: Time.now.to_i,
  last_seen: Time.now.to_i,
  title: "Test Discord",
  description: "Ceci est un test de notification Discord",
  level: "warning",
  status: "open",
  occurrences: 1
}

puts "Configuration Discord:"
config = Notifier.config
if config && config['discord']
  puts "[OK] Config Discord trouvee"
  puts "   - Webhook: #{config['discord']['webhook_url'][0..50]}..."
  puts "   - Enabled: #{config['discord']['enabled']}"
  puts "   - Username: #{config['discord']['username']}"
else
  puts "[ERROR] Config Discord non trouvee"
  exit 1
end

puts ""
puts "Envoi du message Discord..."

result = Notifier.send_discord_webhook(test_ticket)

if result
  puts "[OK] Message Discord envoye !"
  puts ""
  puts "Verifie ton serveur Discord !"
else
  puts "[ERROR] Echec de l'envoi Discord"
end

