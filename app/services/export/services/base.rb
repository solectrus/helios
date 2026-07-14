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

      # .env variable that carries the service's bind-mount host path
      # (e.g. `DB_VOLUME_PATH`). Defined only by services that persist
      # data to a host volume; `persistent?` reads off this.
      def self.volume_env_key
        nil
      end

      def self.persistent?
        !volume_env_key.nil?
      end

      # Host path backing this service's data volume: the user's configured
      # volume_path, or the default ./<service_name>. Single source of truth
      # for Export::Env::Section#volume_path_entry (emits it to .env) and
      # #managed_data_directory (creates the relative source up-front).
      def self.default_host_volume_path(section)
        section.volume_path.presence || "./#{service_name}"
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

      # Full InfluxDB endpoint for a service on a local stack, spelled out
      # rather than left to each image's built-in defaults: a default that
      # changes upstream would silently point the container somewhere else.
      # Host and port stay out of .env because they differ per service (a
      # collector may write to Ingest instead of InfluxDB), and the schema is
      # always http — TLS is terminated at the reverse proxy, never
      # container-to-container.
      def influx_endpoint_vars(host = Influxdb.service_name, port = Influxdb::CONTAINER_PORT)
        ["INFLUX_HOST=#{host}", "INFLUX_PORT=#{port}", 'INFLUX_SCHEMA=http']
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
          local_influx_endpoint_vars + [influx_token_write_var]
        end
      end

      # Where a collector writes to on a local stack: InfluxDB itself, or Ingest
      # (own port) when it recalculates house_power on the way in.
      def local_influx_endpoint_vars
        if collector_influx_target == :ingest
          influx_endpoint_vars(Ingest.service_name, Ingest::PORT)
        else
          influx_endpoint_vars
        end
      end

      def collector_depends_on
        configuration.collectors_only? ? nil : healthy_depends_on([collector_influx_target])
      end

      # Bind mount referencing the service's volume env var; the actual host
      # path is emitted in .env (see `Export::Env#volume_path_entry`). Pair
      # with `managed_data_directory` to create the relative source up-front.
      def bind_mount(container_path)
        "${#{self.class.volume_env_key}}:#{container_path}"
      end

      # The host directory backing this service's data volume, so
      # Export::Builder can create it before `docker compose up`. We can't
      # rely on Docker to auto-create missing bind-mount sources — Synology
      # DSM refuses them ("Bind mount failed: … does not exist").
      #
      # Absolute paths are user-owned (external disk, NAS share) and left
      # untouched; only relative sources are HELIOS-created.
      def managed_data_directory
        path = self.class.default_host_volume_path(volume_section)
        return [] if path.start_with?('/')

        [path]
      end

      def volume_section
        configuration.public_send(self.class.service_name)
      end
    end
  end
end
