require 'json'
require 'fileutils'

module TicketStore
  extend self

  DATA_FILE = File.expand_path('../data/tickets.json', __dir__)

  def init
    FileUtils.mkdir_p(File.dirname(DATA_FILE))
    File.write(DATA_FILE, '[]') unless File.exist?(DATA_FILE)
  end

  def all
    init
    JSON.parse(File.read(DATA_FILE), symbolize_names: true) rescue []
  end

  def create(title, description, level = 'info')
    tickets = all
    new_ticket = {
      id: Time.now.to_i,
      timestamp: Time.now.to_i,
      title: title,
      description: description,
      level: level,
      status: 'open'
    }
    tickets.unshift(new_ticket)
    save(tickets)
    new_ticket
  end

  def update(id, status)
    tickets = all
    ticket = tickets.find { |t| t[:id] == id.to_i }
    return nil unless ticket
    ticket[:status] = status
    save(tickets)
    ticket
  end

  def save(tickets)
    File.write(DATA_FILE, JSON.pretty_generate(tickets))
  end
end
