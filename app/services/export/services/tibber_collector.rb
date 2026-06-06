module Export
  module Services
    class TibberCollector < Base
      def self.service_name
        'tibber-collector'
      end

      def self.config_keys
        ['tibber']
      end

      def self.comment
        'Tibber Collector — Fetches dynamic electricity prices'
      end

      # Runs in every mode, mirroring the forecast-collector: both only fetch
      # from a public API and write to InfluxDB, so neither needs the local
      # hardware that keeps the device collectors off a dashboard_only host
      # (see Configuration::DASHBOARD_ONLY_SOURCES).
      def self.enabled?(configuration)
        configuration.tibber_enabled?
      end

      def to_h
        {
          image: configuration.tibber.image.presence || DockerImages.current(:TIBBER_COLLECTOR),
          environment: tibber_environment,
          depends_on: influxdb_depends_on,
          restart: 'unless-stopped',
        }
      end

      private

      def tibber_environment
        passthrough_vars + explicit_vars + %w[TIBBER_TOKEN]
      end

      # The tibber-collector reads the generic INFLUX_MEASUREMENT; map it to the
      # canonical INFLUX_MEASUREMENT_PRICES .env key so the (future) SENEC
      # charger, which reads INFLUX_MEASUREMENT_PRICES, shares the same value.
      def explicit_vars
        write_measurement_vars('INFLUX_MEASUREMENT_PRICES')
      end
    end
  end
end
