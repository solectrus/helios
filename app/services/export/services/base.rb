module Export
  module Services
    class Base
      def initialize(configuration)
        @configuration = configuration
      end

      def self.enabled?(_configuration)
        true
      end

      def self.service_name
        raise NotImplementedError
      end

      def self.comment
        raise NotImplementedError
      end

      def self.data_directories
        []
      end

      HEALTHCHECK_DEFAULTS = {
        interval: '10s',
        timeout: '5s',
        retries: 5,
        start_period: '30s',
      }.freeze

      # `start_interval` was added in Docker Engine 25.0 — older daemons
      # (e.g. Synology DSM 7.2 with Docker 24.0.2) reject unknown keys.
      START_INTERVAL_MIN_VERSION = Gem::Version.new('25.0').freeze

      private

      attr_reader :configuration

      def healthcheck(*test_cmd, **)
        defaults = HEALTHCHECK_DEFAULTS
        version = Orchestration::Connection.engine_version
        if version && version >= START_INTERVAL_MIN_VERSION
          defaults = defaults.merge(start_interval: '2s')
        end

        defaults.merge(test: test_cmd, **)
      end

      def healthy_depends_on(services)
        services.index_with { { condition: 'service_healthy' } }
      end

      def sensor_environment
        configuration.effective_sensor_mappings.filter_map do |sensor, mapping|
          "INFLUX_SENSOR_#{sensor.upcase}" if mapping.present?
        end
      end

      # Collectors publish to Ingest when enabled — it recalculates house_power before forwarding.
      def collector_influx_target
        configuration.ingest_required? ? :ingest : :influxdb
      end

      def explicit_vars
        vars = ["INFLUX_HOST=#{collector_influx_target}"]
        vars << "INFLUX_PORT=#{Ingest::PORT}" if collector_influx_target == :ingest
        vars
      end
    end
  end
end
