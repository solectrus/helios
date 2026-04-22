module Import
  class ConfigurationImporter
    class UnmanagedDetector
      # All .env variable keys that HELIOS manages (generates in .env)
      MANAGED_ENV_KEYS = %w[
        TZ INSTALLATION_DATE ADMIN_PASSWORD SECRET_KEY_BASE
        APP_HOST INFLUX_POLL_INTERVAL CO2_EMISSION_FACTOR
        FORCE_SSL WEB_CONCURRENCY FRAME_ANCESTORS UI_THEME
        INFLUX_EXCLUDE_FROM_HOUSE_POWER
        LOCKUP_CODEWORD TRUSTED_PROXY_RANGES
        POWER_SPLITTER_INTERVAL
        RETENTION_HOURS STATS_PASSWORD
        POSTGRES_PASSWORD
        INFLUX_PASSWORD INFLUX_ORG INFLUX_BUCKET INFLUX_TOKEN
        INFLUX_ADMIN_TOKEN INFLUX_TOKEN_READ INFLUX_TOKEN_WRITE
        INFLUX_MEASUREMENT INFLUX_MEASUREMENT_SENEC INFLUX_MEASUREMENT_FORECAST
        INFLUX_MEASUREMENT_SHELLY INFLUX_MEASUREMENT_MQTT
        INFLUX_MODE INFLUX_POWER_DATA_TYPE
        APP_DOMAIN LETSENCRYPT_EMAIL
        AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_REGION AWS_BUCKET
        SENEC_ADAPTER SENEC_HOST SENEC_SCHEMA SENEC_LANGUAGE SENEC_INTERVAL
        SENEC_USERNAME SENEC_PASSWORD SENEC_TOTP_URI SENEC_SYSTEM_ID SENEC_IGNORE
        FORECAST_PROVIDER FORECAST_LATITUDE FORECAST_LONGITUDE
        FORECAST_DECLINATION FORECAST_AZIMUTH FORECAST_KWP
        FORECAST_CONFIGURATIONS FORECAST_INTERVAL
        FORECAST_DAMPING_MORNING FORECAST_DAMPING_EVENING
        FORECAST_HORIZON FORECAST_INVERTER
        FORECAST_SOLAR_APIKEY SOLCAST_APIKEY SOLCAST_SITE
        PVNODE_APIKEY PVNODE_PAID PVNODE_EXTRA_PARAMS
        SHELLY_HOST SHELLY_INTERVAL SHELLY_PASSWORD
        SHELLY_CLOUD_SERVER SHELLY_AUTH_KEY SHELLY_DEVICE_ID SHELLY_INVERT_POWER
        MQTT_HOST MQTT_PORT MQTT_SSL MQTT_USERNAME MQTT_PASSWORD
      ].freeze

      # Infrastructure .env keys that HELIOS doesn't generate but are well-known
      # SOLECTRUS vars. These are suppressed from unmanaged to avoid noise.
      INFRASTRUCTURE_ENV_KEYS = %w[
        INFLUX_HOST INFLUX_SCHEMA INFLUX_PORT INFLUX_VOLUME_PATH INFLUX_USERNAME
        DB_HOST DB_USER DB_PASSWORD DB_VOLUME_PATH DB_DATABASE
        REDIS_URL REDIS_VOLUME_PATH
      ].freeze

      # Legacy SOLECTRUS keys that HELIOS absorbs at import time via
      # LegacySensorAdapter and MqttExtractor::DEPRECATED_TOPIC_VARS — once
      # translated into sensors/mappings, the originals would only cause noise
      # if re-emitted.
      LEGACY_CONSUMED_ENV_KEYS = %w[
        INFLUX_MEASUREMENT_PV
        MQTT_FLIP_GRID_POW MQTT_FLIP_BAT_POWER
      ].freeze

      def initialize(reader)
        @reader = reader
      end

      def detect
        data = {}

        unmanaged_services = detect_unmanaged_services
        data['services'] = unmanaged_services if unmanaged_services.present?

        unmanaged_env = detect_unmanaged_env_vars
        data['env_vars'] = unmanaged_env if unmanaged_env.present?

        data.presence
      end

      private

      def detect_unmanaged_services
        raw_services = @reader.raw_compose['services'] || {}
        raw_services
          .reject { |_name, config| managed_service?(config) }
          .presence
      end

      def detect_unmanaged_env_vars
        all_managed = all_managed_env_keys
        @reader
          .raw_env
          .to_h
          .reject { |key, _| all_managed.include?(key) || managed_shelly_env_key?(key) }
          .presence
      end

      # Detect by image rather than service name, so legacy installations that use
      # historical names like 'app' (for SOLECTRUS) or 'db' (for PostgreSQL) are
      # recognized as managed and get migrated to canonical names on export.
      def managed_service?(config)
        StackReader.managed_image?(config['image']) ||
          ShellyExtractor.shelly_image?(config['image'])
      end

      # Pattern-named shelly-collector services reference per-device env vars
      # like SHELLY_DEVICE_ID_FRIDGE and INFLUX_MEASUREMENT_SHELLY_FRIDGE.
      # Treat them as managed so they do not pollute the unmanaged section.
      def managed_shelly_env_key?(key)
        key.start_with?('SHELLY_DEVICE_ID_', 'INFLUX_MEASUREMENT_SHELLY_')
      end

      def all_managed_env_keys
        MANAGED_ENV_KEYS +
          INFRASTRUCTURE_ENV_KEYS +
          LEGACY_CONSUMED_ENV_KEYS +
          MqttExtractor::DEPRECATED_TOPIC_VARS.keys +
          MqttExtractor::DEPRECATED_SPLIT_VARS.keys +
          SensorRegistry::SENSORS.keys.map { |s| "INFLUX_SENSOR_#{s.upcase}" } +
          forecast_indexed_env_keys +
          pvnode_indexed_env_keys +
          mqtt_mapping_env_keys
      end

      def forecast_indexed_env_keys
        (0..3).flat_map do |i|
          ["FORECAST_#{i}_DECLINATION", "FORECAST_#{i}_AZIMUTH", "FORECAST_#{i}_KWP", "SOLCAST_#{i}_SITE"]
        end
      end

      def pvnode_indexed_env_keys
        (0..3).map { |i| "PVNODE_#{i}_EXTRA_PARAMS" }
      end

      def mqtt_mapping_env_keys
        # Detect all MAPPING_N_* keys from the raw .env
        @reader.raw_env.to_h.keys.grep(/\AMAPPING_\d+_/)
      end
    end
  end
end
