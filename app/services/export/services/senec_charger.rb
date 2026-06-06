module Export
  module Services
    class SenecCharger < Base
      def self.service_name
        'senec-charger'
      end

      def self.config_keys
        ['senec_charger']
      end

      def self.comment
        'SENEC Charger — Price-optimized grid charging for SENEC batteries'
      end

      # Full mode only — #senec_charger_offered? gates on the mode itself, so
      # neither a collectors_only nor a dashboard_only host reaches this.
      def self.enabled?(configuration)
        configuration.senec_charger_available? && configuration.senec_charger_enabled?
      end

      def to_h
        {
          image: configuration.senec_charger.image.presence || DockerImages.current(:SENEC_CHARGER),
          environment: charger_environment,
          depends_on: influxdb_depends_on,
          restart: 'unless-stopped',
        }
      end

      private

      def charger_environment
        passthrough_vars + explicit_vars + measurement_vars + senec_vars + charger_vars
      end

      # The charger only reads, so it binds INFLUX_TOKEN to the read token. No
      # collectors_only branch: the charger never runs there (see .enabled?).
      def explicit_vars
        ['INFLUX_HOST=influxdb', influx_token_read_var]
      end

      # Prices come from the Tibber collector, forecast from the forecast
      # collector; both .env keys are guaranteed present by
      # Configuration#senec_charger_available?.
      def measurement_vars
        %w[
          INFLUX_MEASUREMENT_PRICES=${INFLUX_MEASUREMENT_PRICES}
          INFLUX_MEASUREMENT_FORECAST=${INFLUX_MEASUREMENT_FORECAST}
        ]
      end

      # Local SENEC access for steering the battery — shared with senec-collector.
      def senec_vars
        %w[SENEC_HOST SENEC_SCHEMA]
      end

      # The .env section owns the CHARGER_* table; forward exactly what it emits.
      def charger_vars
        Env::SenecCharger::ENTRIES.keys
      end
    end
  end
end
