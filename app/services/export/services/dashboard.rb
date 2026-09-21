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
          config[:labels] = traefik_router_labels(entrypoint: 'websecure', port: 3000)
        else
          config[:ports] = ["#{host_port}:3000"]
        end

        config
      end

      private

      def host_port
        configuration.dashboard.host_port.presence || 3000
      end

      def dashboard_environment
        passthrough_vars + explicit_vars + optional_vars + sensor_environment
      end

      # Variables passed through from .env (name only)
      def passthrough_vars
        %w[TZ INSTALLATION_DATE CURRENCY INFLUX_ORG INFLUX_BUCKET SECRET_KEY_BASE ADMIN_PASSWORD] +
          optional_app_host_var +
          %w[FORCE_SSL WEB_CONCURRENCY]
      end

      # Dropped when the configuration names no address, which it may: the
      # field is not required, and it stays empty wherever HELIOS is only ever
      # reached at a loopback address. The dashboard reads APP_HOST with
      # `.presence` and uses it for one thing, the CORS origin it accepts a
      # request from, so an unset value costs nothing. A name compose passes
      # through but .env never defines would reach the container empty.
      def optional_app_host_var
        configuration.public_host.present? ? %w[APP_HOST] : []
      end

      # Variables with service-specific values (internal Docker references, remappings).
      # The dashboard reads straight from InfluxDB, never through Ingest (which is write-only).
      def explicit_vars
        influx_endpoint_vars + %w[
          REDIS_URL=redis://redis:6379/1
          INFLUX_TOKEN=${INFLUX_TOKEN_READ}
          DB_HOST=postgresql
          DB_USER=postgres
          DB_PASSWORD=${POSTGRES_PASSWORD}
        ]
      end

      def optional_vars
        optional_system_vars + optional_house_power_vars
      end

      def optional_system_vars
        dashboard = configuration.dashboard
        # An empty UI_THEME is dropped: an unset value already means "user
        # picks the theme", so passing UI_THEME through adds nothing.
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
    end
  end
end
