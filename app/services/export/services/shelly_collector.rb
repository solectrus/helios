module Export
  module Services
    class ShellyCollector < Base
      def self.service_name
        'shelly-collector'
      end

      def self.config_keys
        ['shelly']
      end

      def self.comment
        'Shelly Collector — Reads data from Shelly energy meters'
      end

      def self.enabled?(configuration)
        return false if configuration.dashboard_only?

        configuration.shelly_collector_devices.any?
      end

      def self.shelly?(device_data)
        %w[data_source wallbox_vendor heatpump_access battery_vendor].any? do |field|
          device_data.try(field) == 'shelly'
        end
      end

      def to_h
        {
          image: shelly_defaults&.image.presence || DockerImages.current(:SHELLY_COLLECTOR),
          environment: shelly_environment,
          depends_on: collector_depends_on,
          restart: 'unless-stopped',
        }
      end

      private

      def shelly_defaults
        configuration.shelly
      end

      def shelly_collector_devices
        configuration.shelly_collector_devices
      end

      # CSV-mode environment: compose lists only the env names; the values
      # (SHELLY_HOST / SHELLY_DEVICE_ID / INFLUX_MEASUREMENT CSVs, optional
      # INFLUX_MODE, SHELLY_PASSWORD, SHELLY_INVERT_POWER, and cloud
      # credentials) are written to the .env by Export::Env::Shelly. One
      # canonical collector consumes every Shelly device, whether it feeds a
      # `source: shelly` sensor or is a standalone shelly.devices entry.
      def shelly_environment
        passthrough_vars + explicit_vars + optional_vars
      end

      def passthrough_vars
        %w[TZ INFLUX_ORG INFLUX_BUCKET SHELLY_INTERVAL INFLUX_MEASUREMENT] + [identifier_var]
      end

      def identifier_var
        cloud_mode? ? 'SHELLY_DEVICE_ID' : 'SHELLY_HOST'
      end

      def optional_vars
        vars = influx_format_vars
        vars << 'SHELLY_PASSWORD' if shelly_password_referenced?
        vars << 'SHELLY_INVERT_POWER' if shelly_collector_devices.any? { |d| d['invert_power'] }
        vars.concat(cloud_vars) if cloud_mode?
        vars
      end

      def influx_format_vars
        vars = []
        vars << 'INFLUX_MODE' if shelly_defaults&.mode.present?
        vars << 'INFLUX_POWER_DATA_TYPE' if shelly_defaults&.power_data_type.present?
        vars
      end

      # SHELLY_PASSWORD shows up in the compose env list when either the
      # whole stack shares a password (shelly.password) or any individual
      # device carries one — `.env` then emits the bare or CSV form via
      # Export::Env::Shelly#password_entry.
      def shelly_password_referenced?
        shelly_defaults&.password.present? ||
          shelly_collector_devices.any? { |d| d['password'].present? }
      end

      def cloud_vars
        vars = ['SHELLY_CLOUD_SERVER']
        vars << 'SHELLY_AUTH_KEY' if shelly_defaults&.auth_key.present?
        vars
      end

      def cloud_mode?
        shelly_defaults&.connection == 'cloud'
      end
    end
  end
end
