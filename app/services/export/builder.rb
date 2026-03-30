module Export
  class Builder
    # Sections whose defaults are only generated when the section is present in config
    OPTIONAL_SECTIONS = %w[backup].freeze

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

    def stack_path
      Rails.configuration.helios_stack_path
    end

    def compose_builder
      @compose_builder ||= Compose.new(@configuration)
    end

    def create_data_directories!
      compose_builder.data_directories.each do |dir|
        FileUtils.mkdir_p(File.join(stack_path, dir))
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
        next if OPTIONAL_SECTIONS.include?(section) && !@configuration.configured?(section)

        current = @configuration.send(section)
        updates = defaults.transform_values(&:call)
        @configuration.update(section, current.merge(updates))
      end
    end
  end
end
