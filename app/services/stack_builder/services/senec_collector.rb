class StackBuilder
  module Services
    class SenecCollector < Base
      def self.service_name
        'senec-collector'
      end

      def self.comment
        'SENEC data collector'
      end

      def self.enabled?(configuration)
        senec_device(configuration).present?
      end

      # Returns the first inverter device with a SENEC battery vendor
      def self.senec_device(configuration)
        configuration.devices_of('inverter').find do |d|
          d.data.battery_vendor&.start_with?('senec')
        end
      end

      def to_h
        {
          image: 'ghcr.io/solectrus/senec-collector:latest',
          environment: senec_environment,
          depends_on: healthy_depends_on(%i[influxdb]),
          restart: 'unless-stopped',
          healthcheck: healthcheck('CMD-SHELL', 'nc -z 127.0.0.1 3000 || exit 1'),
        }
      end

      private

      def device
        self.class.senec_device(configuration)
      end

      def senec_environment
        base_influx_environment.merge(senec_adapter_environment).merge(senec_optional_environment)
      end

      def base_influx_environment
        {
          'TZ' => '${TZ}',
          'INFLUX_HOST' => 'influxdb',
          'INFLUX_TOKEN' => '${INFLUX_TOKEN}',
          'INFLUX_ORG' => '${INFLUX_ORG}',
          'INFLUX_BUCKET' => '${INFLUX_BUCKET}',
          'INFLUX_MEASUREMENT' => '${INFLUX_MEASUREMENT_SENEC}',
          'SENEC_ADAPTER' => '${SENEC_ADAPTER}',
          'SENEC_INTERVAL' => '${SENEC_INTERVAL}',
        }
      end

      def senec_optional_environment
        env = {}
        env['SENEC_IGNORE'] = '${SENEC_IGNORE}' if device.data.senec_ignore.present?
        env
      end

      def senec_adapter_environment
        if device.data.battery_vendor&.start_with?('senec4')
          senec_cloud_environment
        else
          senec_local_environment
        end
      end

      def senec_cloud_environment
        env = { 'SENEC_USERNAME' => '${SENEC_USERNAME}', 'SENEC_PASSWORD' => '${SENEC_PASSWORD}' }
        env['SENEC_TOTP_URI'] = '${SENEC_TOTP_URI}' if device.data.senec_totp_uri.present?
        env['SENEC_SYSTEM_ID'] = '${SENEC_SYSTEM_ID}' if device.data.senec_system_id.present?
        env
      end

      def senec_local_environment
        {
          'SENEC_HOST' => '${SENEC_HOST}',
          'SENEC_SCHEMA' => '${SENEC_SCHEMA}',
          'SENEC_LANGUAGE' => '${SENEC_LANGUAGE}',
        }
      end
    end
  end
end
