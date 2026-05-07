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

      # Container's INFLUX_TOKEN binds to the role-specific write token so
      # collectors don't get admin or read access.
      def influx_token_write_var
        'INFLUX_TOKEN=${INFLUX_TOKEN_WRITE}'
      end

      def explicit_vars
        if configuration.collectors_only?
          ConfigSchema::INFLUXDB_EXTERNAL_ENV_KEYS + [influx_token_write_var]
        else
          vars = ["INFLUX_HOST=#{collector_influx_target}", influx_token_write_var]
          vars << "INFLUX_PORT=#{Ingest::PORT}" if collector_influx_target == :ingest
          vars
        end
      end

      def collector_depends_on
        configuration.collectors_only? ? nil : healthy_depends_on([collector_influx_target])
      end

      # Bind mount referencing the service's volume env var; the actual host
      # path is emitted in .env (see `Export::Env#volume_path_entry`). Pair
      # with `managed_data_directory` to skip creating the default dir when
      # the user pointed the mount elsewhere.
      def bind_mount(container_path)
        "${#{self.class.volume_env_key}}:#{container_path}"
      end

      def managed_data_directory
        volume_section.volume_path.present? ? [] : [self.class.service_name]
      end

      def volume_section
        configuration.public_send(self.class.service_name)
      end
    end
  end
end
