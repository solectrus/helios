class StackBuilder
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
        passthrough_vars + explicit_vars + device_vars + optional_vars
      end

      def passthrough_vars
        %w[INFLUX_TOKEN INFLUX_ORG INFLUX_BUCKET]
      end

      def explicit_vars
        [
          'INFLUX_HOST=influxdb',
          "SHELLY_HOST=#{csv_from { |_, config| config['shelly_host'] }}",
          "SHELLY_INTERVAL=#{csv_from { |_, config| config['shelly_interval'] || shelly_defaults.interval || '5' }}",
          "INFLUX_MEASUREMENT=#{csv_from { |_, config| config['measurement'] }}",
        ]
      end

      def device_vars
        []
      end

      def optional_vars
        %w[
          shelly_password shelly_cloud_server shelly_auth_key
          shelly_device_id shelly_invert_power
        ].each_with_object([]) do |field, vars|
          values = shelly_sensors.map { |_, config| config[field].presence || '' }
          vars << "#{field.upcase}=#{values.join(',')}" if values.any?(&:present?)
        end
      end

      def csv_from(&)
        shelly_sensors.map(&).join(',')
      end
    end
  end
end
