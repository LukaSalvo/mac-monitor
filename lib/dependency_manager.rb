module DependencyManager
  extend self

  def check_updates
    updates = {
      system: [],
      gems: [],
      os: "Unknown"
    }

    if RbConfig::CONFIG['host_os'] =~ /linux/
      updates[:os] = "Linux"
      # Requires apt permissions, so we just check list
      raw = `apt list --upgradable 2>/dev/null`
      updates[:system] = raw.split("\n").drop(1).map { |l| l.split("/")[0] }
    elsif RbConfig::CONFIG['host_os'] =~ /darwin/
      updates[:os] = "macOS"
      raw = `brew outdated --short 2>/dev/null`
      updates[:system] = raw.split("\n").reject(&:empty?)
    end

    # Check Gems
    raw_gems = `bundle outdated --parseable 2>/dev/null`
    updates[:gems] = raw_gems.split("\n").map { |l| l.split(" ")[1] }.compact

    updates
  end

  def update_gems
    system('bundle update')
  end
end
