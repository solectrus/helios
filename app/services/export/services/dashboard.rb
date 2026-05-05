module Export
  module Services
    class Dashboard < Base
      def self.service_name
        'dashboard'
      end

      def self.config_keys
        ['dashboard']
      end

      def self.comment
        'SOLECTRUS — Web application'
      end

      def self.enabled?(configuration)
        !configuration.collectors_only?
      end

      def to_h
        config = {
          image: configuration.dashboard.image,
          environment: dashboard_environment,
          depends_on: healthy_depends_on(%i[postgresql redis influxdb]),
          restart: 'unless-stopped',
          healthcheck: healthcheck('CMD-SHELL', 'nc -z 127.0.0.1 3000 || exit 1', start_period: '60s'),
        }

        if Traefik.enabled?(configuration)
          config[:labels] = traefik_dashboard_labels
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
        %w[
          TZ INSTALLATION_DATE INFLUX_TOKEN INFLUX_ORG INFLUX_BUCKET SECRET_KEY_BASE ADMIN_PASSWORD
          APP_HOST FORCE_SSL
        ]
      end

      # Variables with service-specific values (internal Docker references, remappings)
      def explicit_vars
        %w[
          REDIS_URL=redis://redis:6379
          INFLUX_HOST=influxdb
          DB_HOST=postgresql
          DB_USER=postgres
          DB_PASSWORD=${POSTGRES_PASSWORD}
          DB_DATABASE=solectrus
          WEB_CONCURRENCY=0
        ]
      end

      def optional_vars
        optional_system_vars + optional_house_power_vars
      end

      def optional_system_vars
        dashboard = configuration.dashboard
        {
          'CO2_EMISSION_FACTOR' => dashboard.co2_emission_factor,
          'FRAME_ANCESTORS' => dashboard.frame_ancestors,
          'UI_THEME' => dashboard.ui_theme,
          'LOCKUP_CODEWORD' => dashboard.lockup_codeword,
          'TRUSTED_PROXY_RANGES' => dashboard.trusted_proxy_ranges,
        }.filter_map { |key, value| key if value.present? }
      end

      def optional_house_power_vars
        configuration.excluded_from_house_power.any? ? %w[INFLUX_EXCLUDE_FROM_HOUSE_POWER] : []
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
