class StackBuilder
  module Services
    class Dashboard < Base
      def self.service_name
        'dashboard'
      end

      def self.comment
        'SOLECTRUS web application'
      end

      def to_h
        config = {
          image: configuration.system.image,
          environment: dashboard_environment,
          depends_on: healthy_depends_on(%i[postgresql redis influxdb]),
          restart: 'unless-stopped',
          healthcheck: healthcheck('CMD-SHELL', 'nc -z 127.0.0.1 3000 || exit 1'),
        }

        if Traefik.enabled?(configuration)
          config[:labels] = traefik_dashboard_labels
          config[:environment] << 'FORCE_SSL=true'
        else
          config[:ports] = ['3000:3000']
        end

        config
      end

      private

      def dashboard_environment
        passthrough_vars + explicit_vars + optional_vars + sensor_environment
      end

      # Variables passed through from .env (name only)
      def passthrough_vars
        %w[TZ INSTALLATION_DATE INFLUX_TOKEN INFLUX_ORG INFLUX_BUCKET SECRET_KEY_BASE ADMIN_PASSWORD]
      end

      # Variables with service-specific values
      def explicit_vars
        sys = configuration.system

        [
          "APP_HOST=#{sys.app_host.presence || 'localhost'}",
          "WEB_CONCURRENCY=#{sys.web_concurrency.presence || '0'}",
          'REDIS_URL=redis://redis:6379',
          'INFLUX_HOST=influxdb',
          "INFLUX_POLL_INTERVAL=#{sys.influx_poll_interval.presence || '5'}",
          'DB_HOST=postgresql',
          'DB_USER=postgres',
          'DB_PASSWORD=${POSTGRES_PASSWORD}',
          'DB_DATABASE=solectrus',
        ]
      end

      def optional_vars
        sys = configuration.system
        vars = []
        add_optional(vars, 'CO2_EMISSION_FACTOR', sys.co2_emission_factor)
        add_optional(vars, 'FRAME_ANCESTORS', sys.frame_ancestors)
        add_optional(vars, 'UI_THEME', sys.ui_theme)
        add_optional(vars, 'LOCKUP_CODEWORD', sys.lockup_codeword)
        add_optional(vars, 'TRUSTED_PROXY_RANGES', sys.trusted_proxy_ranges)
        excluded = configuration.excluded_from_house_power.join(',').presence
        add_optional(vars, 'INFLUX_EXCLUDE_FROM_HOUSE_POWER', excluded)
        vars
      end

      def add_optional(vars, key, value)
        vars << "#{key}=#{value}" if value.present?
      end

      def sensor_environment
        configuration.effective_sensor_mappings.filter_map do |sensor, mapping|
          "INFLUX_SENSOR_#{sensor.upcase}" if mapping.present?
        end
      end

      def traefik_dashboard_labels
        domain = configuration.reverse_proxy.app_domain

        [
          'traefik.enable=true',
          "traefik.http.routers.dashboard.rule=Host(`#{domain}`)",
          'traefik.http.routers.dashboard.entrypoints=websecure',
          'traefik.http.routers.dashboard.tls.certresolver=letsencrypt',
          'traefik.http.services.dashboard.loadbalancer.server.port=3000',
        ]
      end
    end
  end
end
