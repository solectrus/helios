module Import
  class ConfigurationImporter
    class SenecExtractor
      include Helpers

      def initialize(reader)
        @reader = reader
      end

      def enabled?
        @reader.services.key?('senec-collector')
      end

      def section_data
        return unless enabled?

        senec_env = service_env('senec-collector')
        data = {
          'adapter' => senec_env['SENEC_ADAPTER'] || 'local',
          'version' => infer_version(senec_env),
          'interval' => senec_env['SENEC_INTERVAL'],
        }.merge(adapter_section_data(senec_env))

        data.compact.presence
      end

      def image
        Compose.normalize_image(@reader.service('senec-collector')&.dig('image'))
      end

      # InfluxDB measurement the senec-collector writes to. Default 'SENEC'.
      # Used to distinguish sensors actually fed by the senec-collector from
      # sensors that just happen to have a SENEC default mapping but point
      # elsewhere (e.g. a custom `balcony:power` value coming from a Shelly
      # or external writer).
      def measurement
        return nil unless enabled?

        service_env('senec-collector')['INFLUX_MEASUREMENT'].presence || 'SENEC'
      end

      def adapter_section_data(senec_env)
        if senec_env['SENEC_ADAPTER'] == 'cloud'
          { 'username' => senec_env['SENEC_USERNAME'], 'password' => senec_env['SENEC_PASSWORD'],
            'totp_uri' => senec_env['SENEC_TOTP_URI'], 'system_id' => senec_env['SENEC_SYSTEM_ID'],
            'request_mode' => senec_env['SENEC_REQUEST_MODE'] }
        else
          { 'host' => senec_env['SENEC_HOST'], 'schema' => senec_env['SENEC_SCHEMA'],
            'language' => senec_env['SENEC_LANGUAGE'] }
        end
      end

      def device_data
        senec_env = service_env('senec-collector')

        data =
          { 'battery_vendor' => senec_vendor(senec_env) }
          .merge(
            senec_env['SENEC_ADAPTER'] == 'cloud' ? senec_cloud_settings(senec_env) : senec_local_settings(senec_env),
          )
          .merge('senec_interval' => senec_env['SENEC_INTERVAL'])
          .compact

        { type: 'inverter', name: 'SENEC', data: }
      end

      private

      # Legacy installations lack an explicit version marker.
      # Cloud access was previously only supported for V4, local only for V3/V2.1.
      def infer_version(senec_env)
        senec_env['SENEC_ADAPTER'] == 'cloud' ? 'v4' : 'v3'
      end

      def senec_vendor(senec_env)
        infer_version(senec_env) == 'v4' ? 'senec4' : 'senec3'
      end

      def senec_local_settings(senec_env)
        {
          'senec_host' => senec_env['SENEC_HOST'],
          'senec_schema' => senec_env['SENEC_SCHEMA'],
          'senec_language' => senec_env['SENEC_LANGUAGE'],
        }
      end

      def senec_cloud_settings(senec_env)
        {
          'senec_username' => senec_env['SENEC_USERNAME'],
          'senec_password' => senec_env['SENEC_PASSWORD'],
          'senec_totp_uri' => senec_env['SENEC_TOTP_URI'],
          'senec_system_id' => senec_env['SENEC_SYSTEM_ID'],
        }
      end
    end
  end
end
