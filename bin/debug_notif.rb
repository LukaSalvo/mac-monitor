#!/usr/bin/env ruby
require_relative '../lib/notifier'
require_relative '../lib/ticket_store'

puts "🛡️  Test de diagnostic notification..."
puts "----------------------------------------"

# 1. Vérif config
unless Notifier.config
  puts "❌ ERREUR: config/email.yml introuvable ou invalide"
  exit 1
end
puts "✅ Config chargée"

# 2. Création faux ticket
ticket = {
  id: "test-#{Time.now.to_i}",
  title: "Test de Notification Manuel",
  description: "Ceci est un test pour vérifier si les notifs partent.",
  level: "warning",
  status: "open",
  first_seen: Time.now.to_i, # AJOUTÉ !
  timestamp: Time.now.to_i
}

# 3. Test Email
puts "\n📧 Tentative d'envoi Email..."
begin
  Notifier.send_ticket_email(ticket)
  puts "✅ Email envoyé (vérifie ta boîte, même les spams !)"
rescue => e
  puts "❌ ERREUR EMAIL : #{e.message}"
  puts e.backtrace.first
end

# 4. Test Discord
puts "\n💬 Tentative d'envoi Discord..."
begin
  Notifier.send_discord_webhook(ticket)
  puts "✅ Webhook envoyé (vérifie le channel)"
rescue => e
  puts "❌ ERREUR DISCORD : #{e.message}"
  puts e.backtrace.first
end

puts "\n----------------------------------------"
