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
        devices_for(configuration).any?
      end

      def to_h
        {
          image: 'ghcr.io/solectrus/shelly-collector:develop',
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

      def devices
        self.class.devices_for(configuration)
      end

      def shelly_environment
        influx_environment.merge(device_environment)
      end

      def influx_environment
        {
          'INFLUX_HOST' => 'influxdb',
          'INFLUX_TOKEN' => '${INFLUX_TOKEN}',
          'INFLUX_ORG' => '${INFLUX_ORG}',
          'INFLUX_BUCKET' => '${INFLUX_BUCKET}',
        }
      end

      def device_environment
        {
          'SHELLY_HOST' => csv_from { |d| d.data.shelly_host },
          'SHELLY_INTERVAL' => csv_from { |d| d.data.shelly_interval || '5' },
          'INFLUX_MEASUREMENT' => csv_from(&:name),
        }.merge(password_environment)
      end

      def password_environment
        passwords = devices.map { |d| d.data.shelly_password.presence || '' }
        return {} unless passwords.any?(&:present?)

        { 'SHELLY_PASSWORD' => passwords.join(',') }
      end

      def csv_from(&)
        devices.map(&).join(',')
      end
    end
  end
end
