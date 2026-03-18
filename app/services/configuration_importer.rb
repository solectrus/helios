class ConfigurationImporter
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

    persist_chapters!(config)
    persist_devices!(config)

    config
  end

  private

  def build_chapters
    chapters = {
      system: system_chapter_data,
      sensors: sensors_chapter_data,
      reverse_proxy: reverse_proxy_chapter_data,
      backup: backup_chapter_data,
      devices: [],
    }

    chapters[:devices] << senec_device_data if senec_collector?

    chapters
  end

  def persist_chapters!(config)
    config.update_chapter('system', result[:system])
    config.update_chapter('sensors', result[:sensors])
    config.update_chapter('reverse_proxy', result[:reverse_proxy]) if result[:reverse_proxy]
    config.update_chapter('backup', result[:backup]) if result[:backup]
  end

  def persist_devices!(config)
    result[:devices].each do |device|
      config.add_device(device[:kind], device[:name], device[:data])
    end
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

  def reverse_proxy_chapter_data
    return unless @reader.services.key?('traefik')

    domain = extract_domain_from_dashboard_labels
    return unless domain

    { 'enabled' => true, 'app_domain' => domain }
  end

  def extract_domain_from_dashboard_labels
    rule_value = find_traefik_rule_label
    match = rule_value&.match(/Host\(`([^`]+)`\)/)
    match && match[1]
  end

  def find_traefik_rule_label
    labels = @reader.service('dashboard')&.dig('labels') || {}

    if labels.is_a?(Hash)
      labels.find { |k, _| k.include?('routers.dashboard.rule') }&.last
    else
      labels.find { |v| v.to_s.include?('routers.dashboard.rule') }
    end
  end

  def backup_chapter_data
    return unless @reader.services.key?('postgresql-backup')

    {
      'enabled' => true,
      'aws_access_key_id' => @reader.raw_env['AWS_ACCESS_KEY_ID'],
      'aws_secret_access_key' => @reader.raw_env['AWS_SECRET_ACCESS_KEY'],
      'aws_region' => @reader.raw_env['AWS_REGION'],
      'aws_bucket' => @reader.raw_env['AWS_BUCKET'],
    }.compact
  end
end
