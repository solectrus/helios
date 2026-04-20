module Export
  class Builder
    # Sections whose defaults are only generated on demand. The lambda decides
    # whether defaults should be written for this section given the current
    # configuration. Sections not listed here are always populated with defaults.
    OPTIONAL_SECTIONS = {
      'backup' => ->(config) { config.configured?('backup') },
      'ingest' => ->(config) { config.ingest_required? },
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

    def ensure_defaults!
      missing = ConfigSchema.missing_auto_generated(@configuration)
      return if missing.empty?

      missing.each do |section, defaults|
        gate = OPTIONAL_SECTIONS[section]
        next if gate && !gate.call(@configuration)

        current = @configuration.send(section)
        updates = defaults.transform_values(&:call)
        @configuration.update(section, current.merge(updates))
      end
    end
  end
end
