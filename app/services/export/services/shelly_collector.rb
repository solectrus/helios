module Export
  module Services
    class ShellyCollector < Base
      def self.service_name
        'shelly-collector'
      end

      def self.comment
        'Shelly collector'
      end

      def self.enabled?(configuration)
        configuration.shelly_required?
      end

      def self.shelly?(device_data)
        %w[data_source wallbox_vendor heatpump_access battery_vendor].any? do |field|
          device_data.try(field) == 'shelly'
        end
      end

      def to_h
        {
          image: 'ghcr.io/solectrus/shelly-collector:develop',
          environment: shelly_environment,
          depends_on: healthy_depends_on(%i[influxdb]),
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
        passthrough_vars + explicit_vars + optional_vars
      end

      def passthrough_vars
        vars = %w[INFLUX_TOKEN INFLUX_ORG INFLUX_BUCKET SHELLY_INTERVAL INFLUX_MEASUREMENT]
        vars << 'SHELLY_HOST' unless cloud_mode?
        vars
      end

      def explicit_vars
        ['INFLUX_HOST=influxdb']
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
