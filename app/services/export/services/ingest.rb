module Export
  module Services
    class Ingest < Base
      PORT = 4567

      # See https://docs.solectrus.de/referenz/ingest/konfiguration/
      RELEVANT_SENSORS = SensorRegistry::INGEST_SENSORS

      def self.service_name
        'ingest'
      end

      def self.config_keys
        ['ingest']
      end

      def self.volume_env_key
        'INGEST_VOLUME_PATH'
      end

      def self.proxy_subdomain
        'ingest'
      end

      def self.comment
        'Ingest — Ingestion proxy that recalculates house_power for balcony power plants'
      end

      def self.enabled?(configuration)
        configuration.ingest_required?
      end

      # True when a managed Traefik routes Ingest, which it does whenever one
      # runs. An external source then writes over HTTPS, on the same domain as
      # the rest of the stack. It carries the InfluxDB token in a header, which
      # a plain host port would send across the network in the clear.
      def self.traefik_managed_routing?(configuration)
        enabled?(configuration) && Traefik.enabled?(configuration)
      end

      def data_directories
        managed_data_directory
      end

      def to_h
        {
          image: configuration.ingest.image,
          ports: published_ports,
          labels: router_labels,
          environment: ingest_environment,
          volumes: [bind_mount('/app/data')],
          depends_on: healthy_depends_on(%i[influxdb]),
          restart: 'unless-stopped',
          healthcheck: healthcheck('CMD-SHELL', "wget -qO- http://127.0.0.1:#{PORT}/ping || exit 1"),
        }.compact
      end

      private

      # Nothing while Traefik owns the port: HELIOS routes Ingest through it and
      # the entrypoint binds the port, so publishing it here as well would
      # clash. Nothing either on a shared network, where the external proxy
      # reaches Ingest by name.
      def published_ports
        return if traefik_managed_routing? || shared_network_routing?

        ["#{PORT}:#{PORT}"]
      end

      def router_labels
        return traefik_router_labels(entrypoint: 'ingest', port: PORT) if traefik_managed_routing?

        shared_network_router_labels(port: PORT) if shared_network_routing?
      end

      def traefik_managed_routing?
        self.class.traefik_managed_routing?(configuration)
      end

      def ingest_environment
        passthrough_vars + explicit_vars + optional_vars + sensor_environment
      end

      def passthrough_vars
        %w[TZ INFLUX_ORG INFLUX_BUCKET RETENTION_HOURS]
      end

      # Ingest deliberately gets no INFLUX_TOKEN: it is a write proxy that
      # authenticates each downstream write with the token the calling client
      # passes in the `Authorization: Token` header (see solectrus/ingest
      # routes/write.rb + influx_writer.rb), so an env token would be dead config.
      # STATS_PASSWORD reuses ADMIN_PASSWORD so the Ingest stats dashboard shares admin auth.
      def explicit_vars
        influx_endpoint_vars + ['STATS_PASSWORD=${ADMIN_PASSWORD}']
      end

      def optional_vars
        vars = []
        vars << 'INFLUX_EXCLUDE_FROM_HOUSE_POWER' if configuration.excluded_from_house_power.any?
        vars
      end

      def sensor_environment
        mappings = configuration.effective_sensor_mappings
        RELEVANT_SENSORS.filter_map do |sensor|
          "INFLUX_SENSOR_#{sensor.upcase}" if mappings[sensor].present?
        end
      end
    end
  end
end
