class ConfigurationImporter
  MANAGED_SERVICES = %w[
    helios
    dashboard
    postgresql
    redis
    influxdb
    senec-collector
    shelly-collector
    mqtt-collector
    power-splitter
    forecast-collector
    watchtower
  ].freeze

  KNOWN_ENV_VARS = %w[
    TZ
    APP_HOST
    INSTALLATION_DATE
    ADMIN_PASSWORD
    INFLUX_POLL_INTERVAL
    FORCE_SSL
    SECRET_KEY_BASE
    WEB_CONCURRENCY
    FRAME_ANCESTORS
    UI_THEME
    CO2_EMISSION_FACTOR
    POSTGRES_PASSWORD
    INFLUX_EXCLUDE_FROM_HOUSE_POWER
    SENEC_ADAPTER
    SENEC_HOST
    SENEC_SCHEMA
    SENEC_LANGUAGE
    SENEC_INTERVAL
    SENEC_USERNAME
    SENEC_PASSWORD
    SENEC_TOTP_URI
    SENEC_SYSTEM_ID
    SENEC_IGNORE
    INFLUX_HOST
    INFLUX_SCHEMA
    INFLUX_PORT
    INFLUX_VOLUME_PATH
    INFLUX_ORG
    INFLUX_BUCKET
    INFLUX_USERNAME
    INFLUX_PASSWORD
    INFLUX_ADMIN_TOKEN
    INFLUX_TOKEN_WRITE
    INFLUX_TOKEN_READ
    INFLUX_TOKEN
    INFLUX_MEASUREMENT
    SHELLY_HOST
    SHELLY_PASSWORD
    SHELLY_INTERVAL
    SHELLY_INVERT_POWER
    SHELLY_CLOUD_SERVER
    SHELLY_AUTH_KEY
    SHELLY_DEVICE_ID
    MQTT_HOST
    MQTT_PORT
    MQTT_SSL
    MQTT_USERNAME
    MQTT_PASSWORD
    DB_HOST
    DB_USER
    DB_PASSWORD
    DB_VOLUME_PATH
    REDIS_VOLUME_PATH
    REDIS_URL
  ].freeze

  KNOWN_ENV_VAR_PREFIXES = %w[
    INFLUX_SENSOR_
    INFLUX_MEASUREMENT_
    DOCKER_INFLUXDB_INIT_
    MAPPING_
    FORECAST_
    SOLCAST_
    PVNODE_
  ].freeze

  def initialize(stack_reader)
    @reader = stack_reader
  end

  # Extracted chapter data as plain hashes (no DB access)
  def result
    @result ||= build_chapters
  end

  # Persist extracted chapters into the database
  def import!
    config = Configuration.current

    config.update_chapter('system', result[:system])
    config.update_chapter('sensors', result[:sensors])
    config.unmanaged = result[:unmanaged]

    result[:devices].each do |device|
      config.add_device(device[:kind], device[:name], device[:data])
    end

    config
  end

  def unmanaged_services
    @unmanaged_services ||= @reader.services.keys - MANAGED_SERVICES
  end

  def unmanaged_env_vars
    @unmanaged_env_vars ||= @reader.raw_env.keys.reject { |key| known_env_var?(key) }
  end

  private

  def build_chapters
    chapters = {
      system: system_chapter_data,
      sensors: sensors_chapter_data,
      devices: [],
      unmanaged: unmanaged_chapter_data,
    }

    chapters[:devices] << senec_device_data if senec_collector?

    chapters
  end

  # Environment of a specific service
  def service_env(name)
    @reader.service(name)&.dig('environment') || {}
  end

  def system_chapter_data
    system_general_data.merge(system_secrets_data).compact
  end

  def system_general_data
    dashboard_env = service_env('dashboard')

    {
      'timezone' => dashboard_env['TZ'],
      'installation_date' => dashboard_env['INSTALLATION_DATE'],
      'postgresql_image' => @reader.service('postgresql')&.dig('image'),
      'redis_image' => @reader.service('redis')&.dig('image'),
      'influxdb_image' => @reader.service('influxdb')&.dig('image'),
      'dashboard_image' => @reader.service('dashboard')&.dig('image'),
      'helios_image' => @reader.service('helios')&.dig('image'),
      'watchtower_image' => @reader.service('watchtower')&.dig('image'),
    }
  end

  def system_secrets_data
    {
      'postgres_password' => @reader.raw_env['POSTGRES_PASSWORD'],
      'secret_key_base' => @reader.raw_env['SECRET_KEY_BASE'],
      'admin_password' => @reader.raw_env['ADMIN_PASSWORD'],
      'influx_password' => @reader.raw_env['INFLUX_PASSWORD'],
      'influx_org' => @reader.raw_env['INFLUX_ORG'],
      'influx_bucket' => @reader.raw_env['INFLUX_BUCKET'],
      'influx_token' => @reader.raw_env['INFLUX_TOKEN'],
    }
  end

  def senec_collector?
    @reader.services.key?('senec-collector')
  end

  def senec_device_data
    senec_env = service_env('senec-collector')

    data =
      { 'battery_vendor' => senec_vendor(senec_env) }
      .merge(senec_env['SENEC_ADAPTER'] == 'cloud' ? senec_cloud_settings(senec_env) : senec_local_settings(senec_env))
      .merge('senec_interval' => senec_env['SENEC_INTERVAL'])
      .compact

    { kind: 'inverter', name: 'SENEC', data: }
  end

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

  def sensors_chapter_data
    dashboard_env = service_env('dashboard')

    dashboard_env
      .select { |k, _| k.start_with?('INFLUX_SENSOR_') }
      .compact_blank
  end

  def unmanaged_chapter_data
    {
      'services' => unmanaged_service_configs,
      'env_vars' => unmanaged_env_var_values,
    }
  end

  # Raw service configs from compose.yaml (preserving ${VAR} references)
  def unmanaged_service_configs
    raw_services = @reader.raw_compose['services'] || {}
    raw_services.slice(*unmanaged_services)
  end

  # Raw values from .env for unmanaged env vars
  def unmanaged_env_var_values
    unmanaged_env_vars.index_with { |key| @reader.raw_env[key] }.compact
  end

  def known_env_var?(key)
    KNOWN_ENV_VARS.include?(key) ||
      KNOWN_ENV_VAR_PREFIXES.any? { |prefix| key.start_with?(prefix) }
  end
end
