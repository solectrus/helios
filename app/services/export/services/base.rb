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

      # Hash-key path locating this service's settings in `config.yaml`,
      # e.g. `['backup', 'influxdb']`. Nil opts the service out of in-place
      # updates (HELIOS uses self-recreate instead).
      def self.config_keys
        nil
      end

      def data_directories
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
        return ConfigSchema::INFLUXDB_EXTERNAL_ENV_KEYS if configuration.collectors_only?

        vars = ["INFLUX_HOST=#{collector_influx_target}"]
        vars << "INFLUX_PORT=#{Ingest::PORT}" if collector_influx_target == :ingest
        vars
      end

      def collector_depends_on
        configuration.collectors_only? ? nil : healthy_depends_on([collector_influx_target])
      end

      # Bind mount honoring an optional `volume_path` override from config.yaml.
      # Defaults to `./<service_name>`; pair with `managed_data_directory` to
      # skip creating the default dir when the user pointed the mount elsewhere.
      def bind_mount(container_path)
        "#{volume_host_path}:#{container_path}"
      end

      def managed_data_directory
        volume_section.volume_path.present? ? [] : [self.class.service_name]
      end

      def volume_host_path
        volume_section.volume_path.presence || "./#{self.class.service_name}"
      end

      def volume_section
        configuration.public_send(self.class.service_name)
      end
    end
  end
end
