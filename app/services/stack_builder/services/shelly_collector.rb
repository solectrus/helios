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
          data.heatpump_access == 'shelly' ||
          data.battery_vendor == 'shelly'
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
        }.merge(optional_csv_environment)
      end

      def optional_csv_environment
        %w[
          shelly_password shelly_cloud_server shelly_auth_key
          shelly_device_id shelly_invert_power
        ].each_with_object({}) do |field, env|
          env_key = field.upcase
          env.merge!(csv_env(env_key) { |d| d.data.send(field) })
        end
      end

      def csv_env(key, &)
        values = devices.map { |d| yield(d).presence || '' }
        return {} unless values.any?(&:present?)

        { key => values.join(',') }
      end

      def csv_from(&)
        devices.map(&).join(',')
      end
    end
  end
end
