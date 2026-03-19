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
          config[:environment]['FORCE_SSL'] = 'true'
        else
          config[:ports] = ['3000:3000']
        end

        config
      end

      private

      def dashboard_environment
        base_dashboard_environment
          .merge(optional_dashboard_environment)
          .merge(sensor_environment)
      end

      def base_dashboard_environment # rubocop:disable Metrics/MethodLength
        {
          'TZ' => '${TZ}',
          'INSTALLATION_DATE' => '${INSTALLATION_DATE}',
          'APP_HOST' => configuration.system.app_host.presence || 'localhost',
          'WEB_CONCURRENCY' => configuration.system.web_concurrency.presence || '0',
          'REDIS_URL' => 'redis://redis:6379',
          'INFLUX_HOST' => 'influxdb',
          'INFLUX_TOKEN' => '${INFLUX_TOKEN}',
          'INFLUX_ORG' => '${INFLUX_ORG}',
          'INFLUX_BUCKET' => '${INFLUX_BUCKET}',
          'INFLUX_POLL_INTERVAL' => configuration.system.influx_poll_interval.presence || '5',
          'DB_HOST' => 'postgresql',
          'DB_USER' => 'postgres',
          'DB_PASSWORD' => '${POSTGRES_PASSWORD}',
          'DB_DATABASE' => 'solectrus',
          'SECRET_KEY_BASE' => '${SECRET_KEY_BASE}',
          'ADMIN_PASSWORD' => '${ADMIN_PASSWORD}',
        }
      end

      def optional_dashboard_environment
        sys = configuration.system
        env = {}
        add_optional(env, 'CO2_EMISSION_FACTOR', sys.co2_emission_factor)
        add_optional(env, 'FRAME_ANCESTORS', sys.frame_ancestors)
        add_optional(env, 'UI_THEME', sys.ui_theme)
        add_optional(env, 'LOCKUP_CODEWORD', sys.lockup_codeword)
        add_optional(env, 'TRUSTED_PROXY_RANGES', sys.trusted_proxy_ranges)
        add_optional(env, 'INFLUX_EXCLUDE_FROM_HOUSE_POWER', sys.influx_exclude_from_house_power)
        env
      end

      def add_optional(env, key, value)
        env[key] = value if value.present?
      end

      def sensor_environment
        configuration.effective_sensor_mappings.each_with_object({}) do |(sensor, mapping), env|
          next if mapping.blank?

          env["INFLUX_SENSOR_#{sensor.upcase}"] = "${INFLUX_SENSOR_#{sensor.upcase}}"
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
