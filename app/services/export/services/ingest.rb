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

      def self.comment
        'Ingest — Ingestion proxy that recalculates house_power for balcony power plants'
      end

      def self.enabled?(configuration)
        configuration.ingest_required?
      end

      def data_directories
        managed_data_directory
      end

      def to_h
        {
          image: configuration.ingest.image,
          ports: ["#{PORT}:#{PORT}"],
          environment: ingest_environment,
          volumes: [bind_mount('/app/data')],
          depends_on: healthy_depends_on(%i[influxdb]),
          restart: 'unless-stopped',
          healthcheck: healthcheck('CMD-SHELL', "wget -qO- http://127.0.0.1:#{PORT}/ping || exit 1"),
        }
      end

      private

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
        ['INFLUX_HOST=influxdb', 'STATS_PASSWORD=${ADMIN_PASSWORD}']
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
