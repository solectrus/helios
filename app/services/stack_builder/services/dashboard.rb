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
          image: system_data.dashboard_image || 'ghcr.io/solectrus/solectrus:latest',
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
        {
          'TZ' => '${TZ}',
          'INSTALLATION_DATE' => '${INSTALLATION_DATE}',
          'REDIS_URL' => 'redis://redis:6379',
          'INFLUX_HOST' => 'influxdb',
          'INFLUX_TOKEN' => '${INFLUX_TOKEN}',
          'INFLUX_ORG' => '${INFLUX_ORG}',
          'INFLUX_BUCKET' => '${INFLUX_BUCKET}',
          'DB_HOST' => 'postgresql',
          'DB_USER' => 'postgres',
          'DB_PASSWORD' => '${POSTGRES_PASSWORD}',
          'DB_DATABASE' => 'solectrus',
          'SECRET_KEY_BASE' => '${SECRET_KEY_BASE}',
          'ADMIN_PASSWORD' => '${ADMIN_PASSWORD}',
        }
      end

      def traefik_dashboard_labels
        domain = reverse_proxy_data.app_domain

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
