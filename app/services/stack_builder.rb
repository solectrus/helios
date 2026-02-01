class StackBuilder
  DATA_DIRECTORIES = %w[postgresql redis influxdb].freeze

  def initialize(configuration)
    @configuration = configuration
  end

  def compose
    @compose ||= Compose.load
  end

  def env
    @env ||= Env.load
  end

  def write!
    create_data_directories!
    write_compose!
    write_env!
  end

  private

  def stack_path
    Rails.configuration.helios_stack_path
  end

  def create_data_directories!
    DATA_DIRECTORIES.each do |dir|
      path = File.join(stack_path, dir)
      FileUtils.mkdir_p(path) unless File.directory?(path)
    end
  end

  # Compose writing logic

  def write_compose!
    compose.name = 'solectrus'

    add_postgresql_service
    add_redis_service
    add_influxdb_service
    add_dashboard_service

    compose.save
  end

  def add_postgresql_service
    compose.add_service('postgresql', postgresql_config)
  end

  def add_redis_service
    compose.add_service('redis', redis_config)
  end

  def add_influxdb_service
    compose.add_service('influxdb', influxdb_config)
  end

  def add_dashboard_service
    compose.add_service('dashboard', dashboard_config)
  end

  def postgresql_config
    {
      image: 'postgres:18-alpine',
      environment: {
        'POSTGRES_PASSWORD' => '${POSTGRES_PASSWORD}',
        'POSTGRES_DB' => 'solectrus',
      },
      volumes: ['./postgresql:/var/lib/postgresql/data'],
      restart: 'unless-stopped',
      healthcheck: healthcheck_config('CMD-SHELL', 'pg_isready -U postgres'),
    }
  end

  def redis_config
    {
      image: 'redis:8-alpine',
      volumes: ['./redis:/data'],
      restart: 'unless-stopped',
      healthcheck: healthcheck_config('CMD', 'redis-cli', 'ping'),
    }
  end

  def influxdb_config
    {
      image: 'influxdb:2-alpine',
      ports: ['8086:8086'],
      environment: influxdb_environment,
      volumes: ['./influxdb:/var/lib/influxdb2'],
      restart: 'unless-stopped',
      healthcheck: healthcheck_config('CMD', 'influx', 'ping'),
    }
  end

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

  def dashboard_config
    {
      image: 'ghcr.io/solectrus/solectrus:latest',
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

  def dashboard_environment
    common_environment
      .merge(influx_client_environment)
      .merge(database_environment)
      .merge(
        'DB_DATABASE' => 'solectrus',
        'SECRET_KEY_BASE' => '${SECRET_KEY_BASE}',
      )
  end

  def common_environment
    {
      'TZ' => '${TZ}',
      'INSTALLATION_DATE' => '${INSTALLATION_DATE}',
      'REDIS_URL' => 'redis://redis:6379',
    }
  end

  def influx_client_environment
    {
      'INFLUX_HOST' => 'influxdb',
      'INFLUX_TOKEN' => '${INFLUX_TOKEN}',
      'INFLUX_ORG' => '${INFLUX_ORG}',
      'INFLUX_BUCKET' => '${INFLUX_BUCKET}',
    }
  end

  def database_environment
    {
      'DB_HOST' => 'postgresql',
      'DB_USER' => 'postgres',
      'DB_PASSWORD' => '${POSTGRES_PASSWORD}',
    }
  end

  def healthcheck_config(*test_cmd)
    { test: test_cmd, interval: '10s', timeout: '5s', retries: 5 }
  end

  def healthy_depends_on(services)
    services.index_with { { condition: 'service_healthy' } }
  end

  # Env writing logic

  def write_env!
    apply_user_configuration
    apply_secrets
    apply_influxdb_configuration
    env.save
  end

  def apply_user_configuration
    env['INSTALLATION_DATE'] = @configuration.installation_date
    env['TZ'] = @configuration.timezone
  end

  def apply_secrets
    env['POSTGRES_PASSWORD'] ||= generate_secret
    env['SECRET_KEY_BASE'] ||= generate_secret(64)
  end

  def apply_influxdb_configuration
    env['INFLUX_PASSWORD'] ||= generate_secret
    env['INFLUX_ORG'] ||= 'solectrus'
    env['INFLUX_BUCKET'] ||= 'solectrus'
    env['INFLUX_TOKEN'] ||= generate_token
  end

  def generate_secret(length = 32)
    SecureRandom.alphanumeric(length)
  end

  def generate_token
    SecureRandom.hex(32)
  end
end
