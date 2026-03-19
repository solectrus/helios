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
        configuration.senec_required?
      end

      def to_h
        {
          image: 'ghcr.io/solectrus/senec-collector:latest',
          environment: senec_environment,
          depends_on: healthy_depends_on(%i[influxdb]),
          restart: 'unless-stopped',
        }
      end

      private

      def senec_config
        configuration.senec
      end

      def senec_environment
        passthrough_vars + explicit_vars + adapter_vars + optional_vars
      end

      def passthrough_vars
        %w[TZ INFLUX_TOKEN INFLUX_ORG INFLUX_BUCKET INFLUX_MEASUREMENT_SENEC SENEC_ADAPTER SENEC_INTERVAL]
      end

      def explicit_vars
        ['INFLUX_HOST=influxdb']
      end

      def adapter_vars
        if senec_config.adapter == 'cloud'
          senec_cloud_vars
        else
          senec_local_vars
        end
      end

      def senec_cloud_vars
        vars = %w[SENEC_USERNAME SENEC_PASSWORD]
        vars << 'SENEC_TOTP_URI' if senec_config.totp_uri.present?
        vars << 'SENEC_SYSTEM_ID' if senec_config.system_id.present?
        vars
      end

      def senec_local_vars
        %w[SENEC_HOST SENEC_SCHEMA SENEC_LANGUAGE]
      end

      def optional_vars
        senec_config.ignore.present? ? %w[SENEC_IGNORE] : []
      end
    end
  end
end
