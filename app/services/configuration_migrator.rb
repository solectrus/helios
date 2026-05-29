# Applies pending ConfigurationMigrations to config.yaml on boot.
#
# A schema version is tracked at the top level of config.yaml under the key
# `_schema_version`. Files without that key are treated as version 0, so any
# existing installation predating migrations runs through the full chain on
# the next boot. A timestamped backup is written before any change and
# removed once the migration has succeeded — failures leave it behind so the
# original file can be recovered manually.
class ConfigurationMigrator
  include Loggable

  def self.run!
    new(Configuration.path).run!
  end

  def initialize(path)
    @path = path
  end

  def run!
    return :missing unless File.exist?(@path)

    data = Configuration.load_file(@path)
    from = data[Configuration::SCHEMA_VERSION_KEY].to_i
    pending = ConfigurationMigrations.pending(from)
    return :current if pending.empty?

    apply!(data, pending)
    log_migration(from, pending)
    :migrated
  end

  private

  def apply!(data, pending)
    backup_path = backup!
    migrated = pending.reduce(data) { |d, klass| klass.new.up(d) }
    migrated[Configuration::SCHEMA_VERSION_KEY] = ConfigurationMigrations.current_version
    write_atomic!(migrated)
    FileUtils.rm_f(backup_path)
  end

  def log_migration(from, pending)
    logger.info(
      "migrated #{File.basename(@path)} " \
      "from v#{from} to v#{ConfigurationMigrations.current_version} " \
      "(#{pending.map { |m| m.name&.demodulize || m.inspect }.join(', ')})",
    )
  end

  def backup!
    suffix = Time.now.utc.strftime('%Y%m%d%H%M%S')
    target = "#{@path}.pre-migration-#{suffix}.bak"
    FileUtils.cp(@path, target)
    target
  end

  def write_atomic!(data)
    tmp = "#{@path}.tmp"
    File.write(tmp, Configuration.dump(reordered(data)))
    File.rename(tmp, @path)
  end

  # Mirror Configuration#ordered_data: schema version on top, then the
  # canonical section ordering, then everything else (e.g. _unmanaged).
  def reordered(data)
    result = {}
    schema_key = Configuration::SCHEMA_VERSION_KEY
    result[schema_key] = data[schema_key] if data.key?(schema_key)
    Configuration::YAML_ORDER.each { |k| result[k] = data[k] if data.key?(k) }
    data.each { |k, v| result[k] = v unless result.key?(k) }
    result
  end
end
