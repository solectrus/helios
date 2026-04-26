module Export
  class Builder
    # Sections whose defaults are only generated on demand. The lambda decides
    # whether defaults should be written for this section given the current
    # configuration. Sections not listed here are always populated with defaults.
    LOCAL_STACK_ONLY = ->(config) { !config.collectors_only? }
    OPTIONAL_SECTIONS = {
      'backup' => ->(config) { config.configured?('backup') },
      'ingest' => ->(config) { config.ingest_required? },
      'dashboard' => LOCAL_STACK_ONLY,
      'postgresql' => LOCAL_STACK_ONLY,
      'influxdb' => LOCAL_STACK_ONLY,
      'redis' => LOCAL_STACK_ONLY,
    }.freeze

    def initialize(configuration)
      @configuration = configuration
    end

    def write!
      ensure_defaults!
      create_data_directories!
      write_compose!
      write_env!
    end

    # Regenerate compose.yaml/.env only if config.yaml is newer than either of
    # them (or they're missing). Catches drift from direct edits to config.yaml
    # without paying the write cost on every render.
    def write_if_stale!
      write! if stale?
    end

    def stale?
      source_mtime = mtime(Configuration.path)
      return false unless source_mtime

      [::Compose.path, ::Env.path].any? do |target|
        target_mtime = mtime(target)
        target_mtime.nil? || source_mtime > target_mtime
      end
    end

    def compose_content
      compose_builder.to_yaml
    end

    def env_content
      Env.new(@configuration).to_s
    end

    private

    def data_path
      Rails.configuration.data_path
    end

    def compose_builder
      @compose_builder ||= Compose.new(@configuration)
    end

    def create_data_directories!
      compose_builder.data_directories.each do |dir|
        FileUtils.mkdir_p(File.join(data_path, dir))
      end
    end

    def write_compose!
      atomic_write(::Compose.path, compose_content)
    end

    def write_env!
      atomic_write(::Env.path, env_content)
    end

    def atomic_write(path, content)
      tmp_path = "#{path}.tmp"
      ::File.write(tmp_path, content)
      ::File.rename(tmp_path, path)
    end

    def mtime(path)
      ::File.mtime(path)
    rescue Errno::ENOENT
      nil
    end

    def ensure_defaults!
      missing = ConfigSchema.missing_auto_generated(@configuration)
      return if missing.empty?

      missing.each do |section, defaults|
        gate = OPTIONAL_SECTIONS[section]
        next if gate && !gate.call(@configuration)

        current = @configuration.send(section)
        updates = defaults.transform_values { |v| ConfigSchema.resolve_default(v) }
        @configuration.update(section, current.merge(updates))
      end
    end
  end
end
