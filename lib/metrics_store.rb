require 'json'
require 'fileutils'

module MetricsStore
  extend self

  DATA_FILE = File.expand_path('../data/metrics.jsonl', __dir__)

  def init
    FileUtils.mkdir_p(File.dirname(DATA_FILE))
    FileUtils.touch(DATA_FILE) unless File.exist?(DATA_FILE)
  end

  def append(metrics)
    init
    entry = metrics.merge(ts: Time.now.to_i)
    File.open(DATA_FILE, 'a') { |f| f.puts(entry.to_json) }
    entry
  end

  def last_seconds(seconds)
    init
    cutoff = Time.now.to_i - seconds
    File.readlines(DATA_FILE).reverse_each.lazy.map do |line|
      begin
        JSON.parse(line, symbolize_names: true)
      rescue
        nil
      end
    end.compact.take_while { |e| e[:ts].to_i >= cutoff }.to_a
  end
end

