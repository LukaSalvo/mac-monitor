require_relative 'ticket_store'

module FatalDetector
  extend self

  # Optionnel: tu peux pointer un fichier de log via ENV["MONITOR_LOG"]
  PATTERN = /(fatal|fatal error|panic|segfault|exception|stack trace)/i

  def wrap
    yield
  rescue => e
    TicketStore.upsert(
      "Fatal error",
      "#{e.class}: #{e.message}\n" + (e.backtrace || []).first(20).join("\n"),
      "critical",
      fingerprint: e.class.name
    )
    raise
  end

  def scan_log_file(path)
    return unless path && File.exist?(path)
    tail = File.readlines(path).last(200).join
    return unless tail.match?(PATTERN)

    TicketStore.upsert(
      "Fatal error (log)",
      "Détecté dans #{path}\n---\n#{tail[-1500, 1500]}",
      "critical",
      fingerprint: "log:#{path}"
    )
  rescue
    # on n'explose pas parce qu'un log est illisible
  end
end

