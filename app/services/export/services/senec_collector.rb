module Export
  module Services
    class SenecCollector < Base
      def self.service_name
        'senec-collector'
      end

      def self.config_keys
        ['senec']
      end

      def self.comment
        'SENEC Collector — Reads data from SENEC battery storage systems'
      end

      def self.enabled?(configuration)
        return false if configuration.dashboard_only?

        configuration.senec_required? || (configuration.collectors_only? && configuration.senec.present?)
      end

      def to_h
        {
          image: configuration.senec.image.presence || DockerImages.current(:SENEC_COLLECTOR),
          environment: senec_environment,
          depends_on: collector_depends_on,
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
        %w[TZ INFLUX_ORG INFLUX_BUCKET SENEC_ADAPTER SENEC_INTERVAL]
      end

      # senec-collector reads INFLUX_MEASUREMENT, not INFLUX_MEASUREMENT_SENEC —
      # the latter is only the .env name that keeps the per-collector
      # measurements apart. Same remapping as the forecast collector.
      def explicit_vars
        super + ['INFLUX_MEASUREMENT=${INFLUX_MEASUREMENT_SENEC}']
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
        vars << 'SENEC_REQUEST_MODE' if senec_config.request_mode.present?
        vars
      end

      def senec_local_vars
        %w[SENEC_HOST SENEC_SCHEMA SENEC_LANGUAGE]
      end

      def optional_vars
        configuration.senec_ignore.present? ? %w[SENEC_IGNORE] : []
      end
    end
  end
end
