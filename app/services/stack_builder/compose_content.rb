class StackBuilder
  class ComposeContent
    def initialize(system_chapter)
      @system_chapter = system_chapter
    end

    def postgresql
      {
        image: system_chapter['postgresql_image'] || 'postgres:18-alpine',
        environment: {
          'POSTGRES_PASSWORD' => '${POSTGRES_PASSWORD}',
          'POSTGRES_DB' => 'solectrus',
        },
        volumes: ['./postgresql:/var/lib/postgresql'],
        restart: 'unless-stopped',
        healthcheck: healthcheck('CMD-SHELL', 'pg_isready -U postgres'),
      }
    end

    def redis
      {
        image: system_chapter['redis_image'] || 'redis:8-alpine',
        volumes: ['./redis:/data'],
        restart: 'unless-stopped',
        healthcheck: healthcheck('CMD', 'redis-cli', 'ping'),
      }
    end

    def influxdb
      {
        image: system_chapter['influxdb_image'] || 'influxdb:2-alpine',
        ports: ['8086:8086'],
        environment: influxdb_environment,
        volumes: ['./influxdb:/var/lib/influxdb2'],
        restart: 'unless-stopped',
        healthcheck: healthcheck('CMD', 'influx', 'ping'),
      }
    end

    def dashboard
      {
        image: system_chapter['dashboard_image'] || 'ghcr.io/solectrus/solectrus:latest',
        ports: ['3000:3000'],
        environment: dashboard_environment,
        depends_on: healthy_depends_on(%i[postgresql redis influxdb]),
        restart: 'unless-stopped',
        healthcheck: {
          test: ['CMD-SHELL', 'nc -z 127.0.0.1 3000 || exit 1'],
          interval: '10s',
          timeout: '5s',
          retries: 3,
        },
      }
    end

    def watchtower
      {
        image: system_chapter['watchtower_image'] || 'nickfedor/watchtower',
        environment: ['TZ'],
        volumes: ['/var/run/docker.sock:/var/run/docker.sock'],
        command: '--scope solectrus --cleanup',
        restart: 'unless-stopped',
        logging: { options: { 'max-size' => '10m', 'max-file' => '3' } },
        labels: ['com.centurylinklabs.watchtower.scope=solectrus'],
      }
    end

    def helios
      {
        image: system_chapter['helios_image'] || 'ghcr.io/solectrus/helios:develop',
        user: 'root',
        environment: {
          'SECRET_KEY_BASE' => '${HELIOS_SECRET_KEY_BASE}',
          'HELIOS_STACK_PATH' => '/opt/solectrus',
          'HELIOS_HOST_STACK_PATH' => '${HELIOS_HOST_STACK_PATH}',
        },
        volumes: [
          '${HELIOS_HOST_STACK_PATH}:/opt/solectrus',
          '/var/run/docker.sock:/var/run/docker.sock',
        ],
        ports: ['3999:3000'],
        restart: 'unless-stopped',
      }
    end

    private

    attr_reader :system_chapter

    def influxdb_environment
      {
        'DOCKER_INFLUXDB_INIT_MODE' => 'setup',
        'DOCKER_INFLUXDB_INIT_USERNAME' => 'admin',
        'DOCKER_INFLUXDB_INIT_PASSWORD' => '${INFLUX_PASSWORD}',
        'DOCKER_INFLUXDB_INIT_ORG' => '${INFLUX_ORG}',
        'DOCKER_INFLUXDB_INIT_BUCKET' => '${INFLUX_BUCKET}',
        'DOCKER_INFLUXDB_INIT_ADMIN_TOKEN' => '${INFLUX_TOKEN}',
      }
    end

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

    def healthcheck(*test_cmd)
      { test: test_cmd, interval: '10s', timeout: '5s', retries: 5 }
    end

    def healthy_depends_on(services)
      services.index_with { { condition: 'service_healthy' } }
    end
  end
end
