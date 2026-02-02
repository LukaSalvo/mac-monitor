#!/usr/bin/env ruby
# Test d'envoi d'email

require 'bundler/setup'
require_relative '../lib/notifier'

puts "=== Test d'envoi d'email ==="
puts ""

# Créer un ticket de test
test_ticket = {
  id: "test-123",
  first_seen: Time.now.to_i,
  last_seen: Time.now.to_i,
  title: "Test Email",
  description: "Ceci est un test d'envoi d'email",
  level: "warning",
  status: "open",
  occurrences: 1
}

puts "Configuration email:"
config = Notifier.config
if config
  puts "[OK] Fichier config/email.yml trouve"
  puts "   - SMTP: #{config['smtp']['address']}:#{config['smtp']['port']}"
  puts "   - User: #{config['smtp']['user_name']}"
  puts "   - From: #{config['notifications']['from']}"
  puts "   - To: #{config['notifications']['to']}"
  puts "   - Enabled: #{config['notifications']['enabled']}"
else
  puts "[ERROR] Fichier config/email.yml non trouve"
  exit 1
end

puts ""
puts "Tentative d'envoi d'email..."

begin
  result = Notifier.send_ticket_email(test_ticket)
  if result
    puts "[OK] Email envoye avec succes !"
    puts ""
    puts "Verifiez votre boite Gmail: #{config['notifications']['to']}"
  else
    puts "[ERROR] L'envoi a echoue (verifiez les logs ci-dessus)"
  end
rescue => e
  puts "[ERROR] #{e.message}"
  puts ""
  puts "Backtrace:"
  puts e.backtrace.first(10)
end

