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
          'interval' => senec_env['SENEC_INTERVAL'],
          'ignore' => senec_env['SENEC_IGNORE'],
        }

        if senec_env['SENEC_ADAPTER'] == 'cloud'
          data.merge!('username' => senec_env['SENEC_USERNAME'], 'password' => senec_env['SENEC_PASSWORD'],
                      'totp_uri' => senec_env['SENEC_TOTP_URI'], 'system_id' => senec_env['SENEC_SYSTEM_ID'])
        else
          data.merge!('host' => senec_env['SENEC_HOST'], 'schema' => senec_env['SENEC_SCHEMA'],
                      'language' => senec_env['SENEC_LANGUAGE'])
        end

        data.compact.presence
      end

      def device_data
        senec_env = service_env('senec-collector')

        data =
          { 'battery_vendor' => senec_vendor(senec_env) }
          .merge(
            senec_env['SENEC_ADAPTER'] == 'cloud' ? senec_cloud_settings(senec_env) : senec_local_settings(senec_env),
          )
          .merge('senec_interval' => senec_env['SENEC_INTERVAL'])
          .merge('senec_ignore' => senec_env['SENEC_IGNORE'])
          .compact

        { type: 'inverter', name: 'SENEC', data: }
      end

      private

      def senec_vendor(senec_env)
        senec_env['SENEC_ADAPTER'] == 'cloud' ? 'senec4' : 'senec3'
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
