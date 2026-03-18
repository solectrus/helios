class StackBuilder
  module Services
    class ShellyCollector < Base
      attr_reader :device

      def initialize(configuration, device:)
        super(configuration)
        @device = device
      end

      def service_name
        "shelly-#{identifier}"
      end

      def comment
        "Shelly collector for #{device.data.name || device.name}"
      end

      def to_h
        {
          image: 'ghcr.io/solectrus/shelly-collector:latest',
          environment: shelly_environment,
          depends_on: healthy_depends_on(%i[influxdb]),
          restart: 'unless-stopped',
        }
      end

      # Find all devices that use Shelly as data source
      def self.devices_for(configuration)
        configuration.all_devices.select { |d| shelly?(d.data) }
      end

      def self.shelly?(data)
        data.data_source == 'shelly' ||
          data.wallbox_vendor == 'shelly' ||
          data.heatpump_access == 'shelly'
      end

      private

      def shelly_environment
        env = {
          'SHELLY_HOST' => device.data.shelly_host,
          'SHELLY_INTERVAL' => device.data.shelly_interval || '5',
          'INFLUX_HOST' => 'influxdb',
          'INFLUX_TOKEN' => '${INFLUX_TOKEN}',
          'INFLUX_ORG' => '${INFLUX_ORG}',
          'INFLUX_BUCKET' => '${INFLUX_BUCKET}',
          'INFLUX_MEASUREMENT' => measurement_name,
        }

        password = device.data.shelly_password
        env['SHELLY_PASSWORD'] = password if password.present?

        env
      end

      def identifier
        device.name
      end

      alias measurement_name identifier
    end
  end
end
