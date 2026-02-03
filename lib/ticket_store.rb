require 'json'
require 'fileutils'
require 'securerandom'

module TicketStore
  extend self

  DATA_FILE = File.expand_path('../data/tickets.json', __dir__)
  LOCK_FILE = "#{DATA_FILE}.lock"

  def init
    FileUtils.mkdir_p(File.dirname(DATA_FILE))
    File.write(DATA_FILE, '[]') unless File.exist?(DATA_FILE)
  end

  def all
    init
    JSON.parse(File.read(DATA_FILE), symbolize_names: true)
  rescue
    []
  end

  # Sauvegarde atomique + lock basique (évite de casser le JSON si 2 runs en même temps)
  def save(tickets)
    init
    with_lock do
      tmp = "#{DATA_FILE}.tmp"
      File.write(tmp, JSON.pretty_generate(tickets))
      FileUtils.mv(tmp, DATA_FILE)
    end
  end

  def create(title, description, level = 'info', fingerprint: nil)
    tickets = all

    now = Time.now.to_i
    new_ticket = {
      id: SecureRandom.uuid,
      first_seen: now,
      last_seen: now,
      title: title,
      description: description,
      level: level,
      status: 'open',
      occurrences: 1,
      fingerprint: fingerprint
    }

    tickets.unshift(new_ticket)
    save(tickets)
    
    # Envoi de notification email
    notify_ticket_created(new_ticket)
    
    new_ticket
  end

  # Auto-merge: si un ticket OPEN a le même title (+ fingerprint optionnel), on incrémente occurrences au lieu d'en créer un nouveau
def upsert(title, description, level = 'info', fingerprint: nil)
  tickets = all
  now = Time.now.to_i

  matches = tickets.select do |t|
    t[:title] == title && (fingerprint.nil? || t[:fingerprint] == fingerprint)
  end

  if matches.any?
    ticket = matches.first

    # Si le ticket est ferme, NE PAS le reouvrir -> creer un nouveau ticket
    if ticket[:status] == 'closed'
      return create(title, description, level, fingerprint: "#{fingerprint}-#{now}")
    end

    # Fusion des occurrences + timestamps
    total_occ = matches.sum { |t| (t[:occurrences] || 1).to_i }
    first_seen = matches.map { |t| (t[:first_seen] || t[:timestamp] || now).to_i }.min

    ticket[:occurrences] = total_occ + 1   # +1 pour CE nouvel événement
    ticket[:first_seen] = first_seen
    ticket[:last_seen] = now
    ticket[:description] = description
    ticket[:level] = level if more_severe?(level, ticket[:level])

    # Le ticket reste ouvert (pas de réouverture nécessaire)
    ticket[:status] = 'open'

    # Supprime les doublons (tous les autres matches)
    tickets.reject! do |t|
      t != ticket &&
      t[:title] == title &&
      (fingerprint.nil? || t[:fingerprint] == fingerprint)
    end

    save(tickets)
    ticket
  else
    create(title, description, level, fingerprint: fingerprint)
  end
end


  def update_status(id, status)
    tickets = all
    ticket = tickets.find { |t| t[:id].to_s == id.to_s }
    return nil unless ticket
    ticket[:status] = status
    ticket[:closed_at] = Time.now.to_i if status == 'closed'
    save(tickets)
    ticket
  end

  def close_open(title, fingerprint: nil)
    tickets = all
    ticket = tickets.find do |t|
      t[:status] == 'open' &&
      t[:title] == title &&
      (fingerprint.nil? || t[:fingerprint] == fingerprint)
    end
    return nil unless ticket
    ticket[:status] = 'closed'
    ticket[:closed_at] = Time.now.to_i
    save(tickets)
    ticket
  end

  def find_open(title, fingerprint: nil)
    all.find do |t|
      t[:status] == 'open' &&
      t[:title] == title &&
      (fingerprint.nil? || t[:fingerprint] == fingerprint)
    end
  end

  # Notification lors de la creation d'un ticket
  def notify_ticket_created(ticket)
    require_relative 'notifier'
    
    Thread.new do
      begin
        Notifier.send_ticket_email(ticket)
        Notifier.send_discord_webhook(ticket)
      rescue => e
        puts "[NOTIFIER ERROR] #{e.message}"
        puts e.backtrace.join("\n")
      end
    end
  rescue => e
    puts "[ERROR] Failed to spawn notification thread: #{e.message}"
  end

  private

  def with_lock
    init
    FileUtils.touch(LOCK_FILE)
    File.open(LOCK_FILE, 'r') do |f|
      f.flock(File::LOCK_EX)
      yield
    ensure
      f.flock(File::LOCK_UN)
    end
  end

  # Gravité: info < warning < critical
  def more_severe?(new_level, old_level)
    rank = { 'info' => 0, 'warning' => 1, 'critical' => 2 }
    (rank[new_level] || 0) > (rank[old_level] || 0)
  end
end

