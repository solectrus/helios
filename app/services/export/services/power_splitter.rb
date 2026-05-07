module Export
  module Services
    class PowerSplitter < Base
      # Required by power-splitter/lib/config.rb#validate_sensors! — without
      # these mappings the container aborts on startup.
      MANDATORY_SENSORS = %w[grid_import_power house_power].freeze

      def self.service_name
        'power-splitter'
      end

      def self.config_keys
        ['power_splitter']
      end

      def self.comment
        'Power Splitter — Calculates derived power values'
      end

      def self.enabled?(configuration)
        return false if configuration.collectors_only?

        mappings = configuration.effective_sensor_mappings
        MANDATORY_SENSORS.all? { |name| mappings[name].present? }
      end

      def to_h
        {
          image: configuration.power_splitter.image.presence || DockerImages.current(:POWER_SPLITTER),
          environment: power_splitter_environment,
          depends_on: healthy_depends_on(%i[influxdb postgresql redis]),
          restart: 'unless-stopped',
        }
      end

      private

      def power_splitter_environment
        passthrough_vars + explicit_vars + sensor_environment
      end

      # Variables passed through from .env (name only)
      def passthrough_vars
        %w[
          TZ INSTALLATION_DATE INFLUX_TOKEN INFLUX_ORG INFLUX_BUCKET
          POSTGRES_PASSWORD POWER_SPLITTER_INTERVAL
        ]
      end

      # Variables with service-specific values (internal Docker references, remappings)
      def explicit_vars
        %w[
          INFLUX_HOST=influxdb
          REDIS_URL=redis://redis:6379/1
          DB_HOST=postgresql
          DB_USER=postgres
          DB_PASSWORD=${POSTGRES_PASSWORD}
        ]
      end
    end
  end
end
