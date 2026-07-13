module Export
  module Services
    class PowerSplitter < Base
      # Required by power-splitter/lib/config.rb#validate_sensors! — without
      # these mappings the container aborts on startup.
      MANDATORY_SENSORS = %w[grid_import_power house_power].freeze

      # Named consumers the splitter can attribute grid draw to. house_power
      # (the residual house) is always one consumer; the splitter only earns
      # its keep once the grid draw can be divided across a second one, so at
      # least one of these must be mapped on top of the mandatory sensors.
      CONSUMER_SENSORS =
        (%w[wallbox_power heatpump_power] + SensorRegistry::GROUPS.fetch(:custom)).freeze

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
        return false unless MANDATORY_SENSORS.all? { |name| mappings[name].present? }

        CONSUMER_SENSORS.any? { |name| mappings[name].present? }
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
        passthrough_vars + explicit_vars + optional_vars + sensor_environment
      end

      # Variables passed through from .env (name only)
      def passthrough_vars
        %w[
          TZ INSTALLATION_DATE INFLUX_ORG INFLUX_BUCKET
          POSTGRES_PASSWORD POWER_SPLITTER_INTERVAL
        ]
      end

      # The splitter subtracts the excluded consumers from house_power before
      # dividing the grid draw (power-splitter/lib/splitter.rb#custom_power_total).
      # Without this it divides by a house_power that still contains them.
      def optional_vars
        vars = []
        vars << 'INFLUX_EXCLUDE_FROM_HOUSE_POWER' if configuration.excluded_from_house_power.any?
        vars
      end

      # Variables with service-specific values (internal Docker references, remappings)
      def explicit_vars
        %w[
          INFLUX_HOST=influxdb
          INFLUX_TOKEN=${INFLUX_TOKEN_READWRITE}
          REDIS_URL=redis://redis:6379/1
          DB_HOST=postgresql
          DB_USER=postgres
          DB_PASSWORD=${POSTGRES_PASSWORD}
        ]
      end
    end
  end
end
