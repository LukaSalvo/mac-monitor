require_relative 'ticket_store'

module TicketEngine
  extend self

  # Seuils + seuils de "retour à la normale" (hystérésis) pour éviter open/close/open/close en boucle
  RULES = [
    {
      key: :cpu_percent,
      title: "CPU élevé",
      level: "warning",
      trigger: 85,
      clear: 70,
      unit: "%"
    },
    {
      key: :disk_percent,
      title: "Disque presque plein",
      level: "critical",
      trigger: 90,
      clear: 85,
      unit: "%"
    },
    {
      key: :ram_free_mb,
      title: "Mémoire faible",
      level: "warning",
      trigger: 800,   # en-dessous de 800 MB libres -> incident
      clear: 1200,
      unit: "MB",
      inverted: true  # "plus petit = pire"
    }
  ]

  def run(metrics)
    RULES.each do |r|
      value = metrics[r[:key]]
      next if value.nil?

      fingerprint = r[:key].to_s
      open_ticket = TicketStore.find_open(r[:title], fingerprint: fingerprint)

      if triggered?(r, value)
        TicketStore.upsert(
          r[:title],
          "#{r[:key]}=#{value}#{r[:unit]} (seuil #{r[:trigger]}#{r[:unit]})",
          r[:level],
          fingerprint: fingerprint
        )
      elsif open_ticket && cleared?(r, value)
        TicketStore.close_open(r[:title], fingerprint: fingerprint)
      end
    end
  end

  private

  def triggered?(rule, value)
    if rule[:inverted]
      value.to_f < rule[:trigger].to_f
    else
      value.to_f > rule[:trigger].to_f
    end
  end

  def cleared?(rule, value)
    if rule[:inverted]
      value.to_f > rule[:clear].to_f
    else
      value.to_f < rule[:clear].to_f
    end
  end
end

