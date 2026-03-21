module Export
  module Services
    class PowerSplitter < Base
      def self.service_name
        'power-splitter'
      end

      def self.comment
        'Calculates derived power values'
      end

      def self.enabled?(configuration)
        configuration.ingest_required?
      end

      def to_h
        {
          image: 'ghcr.io/solectrus/power-splitter:latest',
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
        %w[TZ INSTALLATION_DATE INFLUX_TOKEN INFLUX_ORG INFLUX_BUCKET POSTGRES_PASSWORD]
      end

      # Variables with service-specific values
      def explicit_vars
        %w[
          INFLUX_HOST=influxdb
          REDIS_URL=redis://redis:6379/1
          DB_HOST=postgresql
          DB_USER=postgres
          DB_PASSWORD=${POSTGRES_PASSWORD}
        ]
      end

      def optional_vars
        interval = configuration.system.power_splitter_interval
        interval.present? ? ["POWER_SPLITTER_INTERVAL=#{interval}"] : []
      end

      def sensor_environment
        configuration.effective_sensor_mappings.filter_map do |sensor, mapping|
          "INFLUX_SENSOR_#{sensor.upcase}" if mapping.present?
        end
      end
    end
  end
end
