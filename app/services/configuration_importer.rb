require 'open3'
require 'tmpdir'
require 'fileutils'
require 'yaml'

class ConfigurationImporter
  class Error < StandardError; end

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

  def initialize(compose_path:, env_path:)
    @compose_path = compose_path
    @env_path = env_path
  end

  def result
    @result ||= build_configuration
  end

  def unmanaged_services
    @unmanaged_services ||= service_names - MANAGED_SERVICES
  end

  def unmanaged_env_vars
    @unmanaged_env_vars ||= merged_env.keys.reject { |key| known_env_var?(key) }
  end

  private

  def resolved_config
    @resolved_config ||= run_compose_config
  end

  def run_compose_config
    Dir.mktmpdir do |tmpdir|
      FileUtils.cp(@compose_path, File.join(tmpdir, 'compose.yaml'))
      FileUtils.cp(@env_path, File.join(tmpdir, '.env'))

      stdout, stderr, status = Open3.capture3('docker', 'compose', 'config', chdir: tmpdir)
      raise Error, "docker compose config failed: #{stderr.presence || stdout}" unless status.success?

      YAML.safe_load(stdout, permitted_classes: [Symbol]) || {}
    end
  end

  def service_names
    @service_names ||= resolved_config['services']&.keys || []
  end

  def merged_env
    @merged_env ||=
      resolved_config['services']
      &.values
      &.flat_map { |s| (s['environment'] || {}).to_a }
      .to_h
  end

  def build_configuration
    config = Configuration.current
    import_system_chapter(config)
    import_inverter_chapter(config) if senec_collector?
    import_sensors_chapter(config)
    config
  end

  def import_system_chapter(config)
    config.update_chapter(
      'system',
      {
        'timezone' => merged_env['TZ'],
        'installation_date' => merged_env['INSTALLATION_DATE'],
        'postgresql_image' => service_image('postgresql'),
        'redis_image' => service_image('redis'),
        'influxdb_image' => service_image('influxdb'),
        'dashboard_image' => service_image('dashboard'),
      }.compact,
    )
  end

  def service_image(name)
    resolved_config.dig('services', name, 'image')
  end

  def senec_collector?
    service_names.include?('senec-collector')
  end

  def import_inverter_chapter(config)
    data =
      { 'battery_vendor' => senec_vendor }
      .merge(merged_env['SENEC_ADAPTER'] == 'cloud' ? senec_cloud_settings : senec_local_settings)
      .merge('senec_interval' => merged_env['SENEC_INTERVAL'])
      .compact

    config.add_device('inverter', 'SENEC', data)
  end

  def senec_vendor
    merged_env['SENEC_ADAPTER'] == 'cloud' ? 'senec4' : 'senec3'
  end

  def senec_local_settings
    {
      'senec_host' => merged_env['SENEC_HOST'],
      'senec_schema' => merged_env['SENEC_SCHEMA'],
      'senec_language' => merged_env['SENEC_LANGUAGE'],
    }
  end

  def senec_cloud_settings
    {
      'senec_username' => merged_env['SENEC_USERNAME'],
      'senec_password' => merged_env['SENEC_PASSWORD'],
      'senec_totp_uri' => merged_env['SENEC_TOTP_URI'],
      'senec_system_id' => merged_env['SENEC_SYSTEM_ID'],
    }
  end

  def import_sensors_chapter(config)
    mappings =
      merged_env
      .select { |k, _| k.start_with?('INFLUX_SENSOR_') }
      .compact_blank

    config.update_chapter('sensors', mappings)
  end

  def known_env_var?(key)
    KNOWN_ENV_VARS.include?(key) ||
      KNOWN_ENV_VAR_PREFIXES.any? { |prefix| key.start_with?(prefix) }
  end
end
