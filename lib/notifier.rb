require 'mail'
require 'yaml'
require 'net/http'
require 'json'
require 'uri'

module Notifier
  extend self

  def config
    @config ||= begin
      config_file = File.expand_path('../config/email.yml', __dir__)
      if File.exist?(config_file)
        YAML.load_file(config_file)
      else
        puts "[WARNING] Email config not found at #{config_file}"
        nil
      end
    end
  end

  def setup_mail
    return false unless config && config['notifications']['enabled']
    
    cfg = config
    
    Mail.defaults do
      delivery_method :smtp, {
        address: cfg['smtp']['address'],
        port: cfg['smtp']['port'],
        domain: cfg['smtp']['domain'],
        user_name: cfg['smtp']['user_name'],
        password: cfg['smtp']['password'],
        authentication: cfg['smtp']['authentication'],
        enable_starttls_auto: cfg['smtp']['enable_starttls_auto']
      }
    end
    true
  rescue => e
    puts "[ERROR] Failed to setup mail: #{e.message}"
    false
  end

  def send_ticket_email(ticket)
    return false unless setup_mail
    
    cfg = config
    
    level_emoji = {
      'info' => 'ℹ️',
      'warning' => '⚠️',
      'critical' => '🚨'
    }
    
    emoji = level_emoji[ticket[:level]] || '📋'
    subject = "[Mac Monitor] #{emoji} #{ticket[:title]}"
    
    body = <<~EMAIL
      Nouveau Ticket d'Incident
      ═══════════════════════════════════════
      
      ID: #{ticket[:id]}
      #{emoji} Niveau: #{ticket[:level].upcase}
      Titre: #{ticket[:title]}
      
      Description:
      #{ticket[:description]}
      
      Première détection: #{Time.at(ticket[:first_seen]).strftime('%Y-%m-%d %H:%M:%S')}
      Occurrences: #{ticket[:occurrences] || 1}
      Statut: #{ticket[:status]}
      
      Voir le dashboard: http://localhost:3000
      
      ═══════════════════════════════════════
      Mac Monitor - Système de surveillance automatique
    EMAIL
    
    Mail.deliver do
      from     cfg['notifications']['from']
      to       cfg['notifications']['to']
      subject  subject
      body     body
    end
    
    puts "[EMAIL SENT] #{subject} to #{cfg['notifications']['to']}"
    true
  rescue => e
    puts "[ERROR] Failed to send email: #{e.message}"
    puts e.backtrace.first(5)
    false
  end

  def send_discord_webhook(ticket)
    return false unless config && config['discord'] && config['discord']['enabled']
    
    webhook_url = config['discord']['webhook_url']
    return false if webhook_url.nil? || webhook_url.empty?
    
    level_colors = {
      'info' => 3447003,      # Bleu
      'warning' => 16776960,  # Jaune
      'critical' => 15158332  # Rouge
    }
    
    level_emoji = {
      'info' => 'ℹ️',
      'warning' => '⚠️',
      'critical' => '🚨'
    }
    
    color = level_colors[ticket[:level]] || 3447003
    emoji = level_emoji[ticket[:level]] || '📋'
    
    payload = {
      username: config['discord']['username'] || 'Mac Monitor',
      avatar_url: config['discord']['avatar_url'],
      embeds: [{
        title: "#{emoji} Nouveau Ticket",
        description: ticket[:title],
        color: color,
        fields: [
          { name: 'ID', value: ticket[:id], inline: true },
          { name: 'Niveau', value: ticket[:level].upcase, inline: true },
          { name: 'Statut', value: ticket[:status], inline: true },
          { name: 'Description', value: ticket[:description], inline: false },
          { name: 'Occurrences', value: (ticket[:occurrences] || 1).to_s, inline: true },
          { name: 'Détection', value: Time.at(ticket[:first_seen]).strftime('%Y-%m-%d %H:%M:%S'), inline: true }
        ],
        footer: { text: 'Mac Monitor' },
        timestamp: Time.now.strftime('%Y-%m-%dT%H:%M:%S%:z')
      }]
    }
    
    uri = URI.parse(webhook_url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    
    request = Net::HTTP::Post.new(uri.path, { 'Content-Type' => 'application/json' })
    request.body = payload.to_json
    
    response = http.request(request)
    
    if response.code.to_i == 204
      puts "[DISCORD SENT] #{ticket[:title]}"
      true
    else
      puts "[ERROR] Discord webhook failed: #{response.code} #{response.body}"
      false
    end
  rescue => e
    puts "[ERROR] Failed to send Discord: #{e.message}"
    false
  end

  # Ancienne méthode (compatibilité)
  def send_discord(title, message, color = 16711680)
    puts "[NOTIFICATION] #{title}: #{message}"
    true
  end
end