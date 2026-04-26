module Export
  module Services
    class ShellyCollector < Base
      def self.service_name
        'shelly-collector'
      end

      def self.comment
        'Shelly Collector — Reads data from Shelly energy meters'
      end

      def self.enabled?(configuration)
        return false if configuration.dashboard_only?

        configuration.shelly_required? || (configuration.collectors_only? && collectors_only_enabled?(configuration))
      end

      def self.collectors_only_enabled?(configuration)
        Array(configuration.shelly&.devices).any?
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

      def shelly_sensors
        @shelly_sensors ||= configuration.sensors_with_source('shelly')
      end

      def shelly_defaults
        configuration.shelly
      end

      def shelly_environment
        return collectors_only_environment if configuration.collectors_only?

        passthrough_vars + explicit_vars + optional_vars
      end

      # In collectors_only mode the compose only lists env names; the values
      # (SHELLY_HOST / INFLUX_MEASUREMENT CSVs, optional INFLUX_MODE and
      # SHELLY_PASSWORD) are written to the .env by Export::Env.
      def collectors_only_environment
        base = ConfigSchema::INFLUXDB_EXTERNAL_ENV_KEYS + %w[INFLUX_TOKEN INFLUX_ORG INFLUX_BUCKET SHELLY_INTERVAL]
        base + collectors_only_device_vars + collectors_only_extra_vars
      end

      def collectors_only_device_vars
        devices = Array(shelly_defaults&.devices)
        vars = []
        vars << 'SHELLY_HOST' if devices.any? { |d| d['host'].present? }
        vars << 'INFLUX_MEASUREMENT' if devices.any? { |d| d['measurement'].present? }
        vars
      end

      def collectors_only_extra_vars
        vars = []
        vars << 'INFLUX_MODE' if shelly_defaults&.mode.present?
        vars << 'SHELLY_PASSWORD' if shelly_defaults&.password.present?
        vars
      end

      def passthrough_vars
        vars = %w[INFLUX_TOKEN INFLUX_ORG INFLUX_BUCKET SHELLY_INTERVAL INFLUX_MEASUREMENT]
        vars << 'SHELLY_HOST' unless cloud_mode?
        vars
      end

      def optional_vars
        per_sensor_optional_vars + global_optional_vars
      end

      def per_sensor_optional_vars
        %w[shelly_password shelly_device_id shelly_invert_power].each_with_object([]) do |field, vars|
          values = shelly_sensors.map { |_, config| config[field].presence || '' }
          vars << field.upcase if values.any?(&:present?)
        end
      end

      def global_optional_vars
        return [] unless cloud_mode?

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
