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

        configuration.shelly_required? || devices_present?(configuration)
      end

      # True when shelly.devices carries one or more entries — set by the
      # importer for multi-device stacks (CSV-valued single service, or
      # several shelly-collector-<suffix> services). collectors-only mode
      # always falls into this bucket because shelly.devices is the only
      # surface for Shelly topology there.
      def self.devices_present?(configuration)
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
        return devices_environment if self.class.devices_present?(configuration)

        passthrough_vars + explicit_vars + optional_vars
      end

      # CSV-mode environment: compose lists only env names; the values
      # (SHELLY_HOST / SHELLY_DEVICE_ID / INFLUX_MEASUREMENT CSVs, optional
      # INFLUX_MODE, SHELLY_PASSWORD, and cloud credentials) are written to
      # the .env by Export::Env. Used for both collectors-only stacks and
      # full-mode multi-device setups, which share the same single-container
      # CSV shape on the wire.
      def devices_environment
        base = %w[TZ] + explicit_vars + %w[INFLUX_ORG INFLUX_BUCKET SHELLY_INTERVAL]
        base + devices_id_vars + devices_extra_vars
      end

      def devices_id_vars
        devices = Array(shelly_defaults&.devices)
        vars = [devices_identifier_var(devices)].compact
        vars << 'INFLUX_MEASUREMENT' if devices.any? { |d| d['measurement'].present? }
        vars
      end

      def devices_identifier_var(devices)
        if cloud_mode?
          'SHELLY_DEVICE_ID' if devices.any? { |d| d['device_id'].present? }
        elsif devices.any? { |d| d['host'].present? }
          'SHELLY_HOST'
        end
      end

      def devices_extra_vars
        vars = []
        vars << 'INFLUX_MODE' if shelly_defaults&.mode.present?
        vars << 'INFLUX_POWER_DATA_TYPE' if shelly_defaults&.power_data_type.present?
        vars << 'SHELLY_PASSWORD' if shelly_password_referenced?
        vars.concat(devices_cloud_vars) if cloud_mode?
        vars
      end

      # SHELLY_PASSWORD shows up in the compose env list when either the
      # whole stack shares a password (shelly.password) or any individual
      # device carries one — `.env` then emits the bare or CSV form via
      # Export::Env::Shelly#password_entry.
      def shelly_password_referenced?
        shelly_defaults&.password.present? ||
          Array(shelly_defaults&.devices).any? { |d| d['password'].present? }
      end

      def devices_cloud_vars
        vars = []
        vars << 'SHELLY_CLOUD_SERVER' if shelly_defaults&.cloud_server.present?
        vars << 'SHELLY_AUTH_KEY' if shelly_defaults&.auth_key.present?
        vars
      end

      def passthrough_vars
        vars = %w[TZ INFLUX_ORG INFLUX_BUCKET SHELLY_INTERVAL INFLUX_MEASUREMENT]
        vars << 'SHELLY_HOST' unless cloud_mode?
        vars
      end

      def optional_vars
        per_sensor_optional_vars + influx_optional_vars + global_optional_vars
      end

      def influx_optional_vars
        vars = []
        vars << 'INFLUX_MODE' if shelly_defaults&.mode.present?
        vars << 'INFLUX_POWER_DATA_TYPE' if shelly_defaults&.power_data_type.present?
        vars
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
