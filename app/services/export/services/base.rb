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
      # e.g. `['dashboard']`. Nil opts the service out of in-place
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

      # Whether an external proxy routes this service at all. Every enabled
      # routable service does, except the InfluxDB the user keeps inside the
      # stack, which overrides this.
      def self.externally_routable?(configuration)
        enabled?(configuration)
      end

      # The subdomain an external proxy routes this service at. The dashboard
      # answers at the address itself and returns nil here; every other
      # routable service takes a name of its own in front of it.
      #
      # One table for the three places that have to agree on it: the labels
      # HELIOS writes onto a shared network, the file it generates for a
      # Traefik that routes host ports (Export::TraefikConfig) and the Open
      # button of a service (Export::PublicUrl).
      def self.proxy_subdomain
        nil
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

      # Seconds Docker waits after the stop signal before it sends SIGKILL.
      # Docker's default of 10s is too short for the databases: PostgreSQL
      # treats its stop signal as a fast shutdown and writes a checkpoint
      # first, InfluxDB flushes its WAL into TSM files. On slow storage with
      # a long history either can exceed 10s, and the SIGKILL then leaves a
      # data directory that only crash recovery can open. The PostgreSQL image
      # documents the same recommendation next to its own `STOPSIGNAL SIGINT`.
      #
      # Watchtower ignores `stop_grace_period` and uses WATCHTOWER_TIMEOUT
      # instead, so `Export::Env::Watchtower` emits this same value.
      STOP_GRACE_PERIOD = '60s'.freeze

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

      # Read-only counterpart for services that only query InfluxDB (e.g. the
      # SENEC charger reading prices and forecast).
      def influx_token_read_var
        'INFLUX_TOKEN=${INFLUX_TOKEN_READ}'
      end

      # InfluxDB env vars every collector passes through unchanged: TZ plus the
      # org/bucket names, and the external connection vars (host/port/schema) in
      # collectors_only mode. Services that read more (senec, dashboard, …)
      # override this.
      def passthrough_vars
        vars = %w[TZ INFLUX_ORG INFLUX_BUCKET]
        vars += ConfigSchema::INFLUXDB_EXTERNAL_ENV_KEYS if configuration.collectors_only?
        vars
      end

      def explicit_vars
        if configuration.collectors_only?
          ConfigSchema::INFLUXDB_EXTERNAL_ENV_KEYS + [influx_token_write_var]
        else
          local_influx_endpoint_vars + [influx_token_write_var]
        end
      end

      # Write-collector env pointing the generic INFLUX_MEASUREMENT at a
      # canonical per-service .env key (e.g. INFLUX_MEASUREMENT_PRICES). Shared
      # by the collectors that write a single measurement under their own name
      # (forecast, tibber) and target InfluxDB directly rather than via Ingest.
      def write_measurement_vars(measurement_key)
        measurement = "INFLUX_MEASUREMENT=${#{measurement_key}}"
        return [influx_token_write_var, measurement] if configuration.collectors_only?

        ['INFLUX_HOST=influxdb', influx_token_write_var, measurement]
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

      # Services that target InfluxDB directly, bypassing Ingest — their data
      # must not be rewritten by the house_power recalculation.
      def influxdb_depends_on
        configuration.collectors_only? ? nil : healthy_depends_on(%i[influxdb])
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

      # Router labels for a service the managed Traefik routes at the
      # configured address. The router and the load balancer are named after
      # the service, so the entrypoint and the container port are all a caller
      # has to name.
      def traefik_router_labels(entrypoint:, port:, host: configuration.public_host,
                                certresolver: Traefik.certresolver(configuration))
        name = self.class.service_name

        labels = [
          'traefik.enable=true',
          "traefik.http.routers.#{name}.rule=Host(`#{host}`)",
          "traefik.http.routers.#{name}.entrypoints=#{entrypoint}",
        ]
        labels << "traefik.http.routers.#{name}.tls.certresolver=#{certresolver}" if certresolver.present?
        labels << "traefik.http.services.#{name}.loadbalancer.server.port=#{port}"
        labels
      end

      # Router labels for a proxy that reads them off the shared network the
      # stack joined (see Configuration#reverse_proxy_on_shared_network?), or
      # nothing where that proxy carries its own routes. The entrypoint and the
      # resolver are that proxy's, not ours, so both come from the
      # configuration, and the resolver may be left out where the proxy holds
      # its certificates some other way.
      #
      # The dashboard answers at the address itself, every other service at a
      # subdomain of it, which is the same split Export::PublicUrl and
      # Export::TraefikConfig name, so the three cannot lead apart.
      def shared_network_router_labels(port:)
        return unless configuration.reverse_proxy_labels?

        proxy = configuration.reverse_proxy
        subdomain = self.class.proxy_subdomain
        host = subdomain ? "#{subdomain}.#{configuration.public_host}" : configuration.public_host

        traefik_router_labels(
          entrypoint: proxy.proxy_entrypoint,
          port:,
          host:,
          certresolver: proxy.proxy_certresolver.presence,
        ) + [network_label]
      end

      # Which of its networks the proxy connects to. A routed service is on two
      # of them, the stack's own and the shared one, while the proxy is on the
      # shared one alone. Where no label names the network, Traefik takes one
      # of the two at random, and half of the time that is the address it
      # cannot reach.
      def network_label
        "traefik.docker.network=#{configuration.reverse_proxy_network}"
      end

      # Whether an external proxy reaches this service over a shared network
      # instead of a published host port. The service then publishes nothing:
      # the proxy is on that network and reaches it by name.
      def shared_network_routing?
        configuration.reverse_proxy_on_shared_network?
      end
    end
  end
end
