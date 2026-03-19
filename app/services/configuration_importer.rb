class ConfigurationImporter
  def initialize(stack_reader)
    @reader = stack_reader
  end

  # Extracted data as plain hashes (no DB access)
  def result
    @result ||= build_result
  end

  # Persist extracted data into config.yaml
  def import!
    config = Configuration.current

    persist_singletons!(config)
    persist_devices!(config)

    config
  end

  private

  def build_result
    data = {
      system: system_data,
      postgresql: postgresql_data,
      influxdb: influxdb_data,
      redis: redis_data,
      watchtower: watchtower_data,
      sensors: sensors_data,
      reverse_proxy: reverse_proxy_data,
      backup: backup_data,
      devices: [],
    }

    data[:devices] << senec_device_data if senec_collector?

    data
  end

  def persist_singletons!(config)
    %i[system postgresql influxdb redis watchtower sensors reverse_proxy backup].each do |key|
      config.update(key.to_s, result[key]) if result[key]
    end
  end

  def persist_devices!(config)
    result[:devices].each do |device|
      config.add(device[:type], device[:name], device[:data])
    end
  end

  # Environment of a specific service
  def service_env(name)
    @reader.service(name)&.dig('environment') || {}
  end

  def system_data
    dashboard_env = service_env('dashboard')

    {
      'timezone' => dashboard_env['TZ'],
      'installation_date' => dashboard_env['INSTALLATION_DATE'],
      'image' => @reader.service('dashboard')&.dig('image'),
      'admin_password' => @reader.raw_env['ADMIN_PASSWORD'],
      'secret_key_base' => @reader.raw_env['SECRET_KEY_BASE'],
    }.compact
  end

  def redis_data
    image_data_for('redis')
  end

  def watchtower_data
    image_data_for('watchtower')
  end

  def image_data_for(service_name)
    image = @reader.service(service_name)&.dig('image')
    { 'image' => image }.compact
  end

  def postgresql_data
    {
      'image' => @reader.service('postgresql')&.dig('image'),
      'password' => @reader.raw_env['POSTGRES_PASSWORD'],
    }.compact
  end

  def influxdb_data
    {
      'image' => @reader.service('influxdb')&.dig('image'),
      'password' => @reader.raw_env['INFLUX_PASSWORD'],
      'org' => @reader.raw_env['INFLUX_ORG'],
      'bucket' => @reader.raw_env['INFLUX_BUCKET'],
      'token' => @reader.raw_env['INFLUX_TOKEN'],
    }.compact
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

    { type: 'inverter', name: 'SENEC', data: }
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

  def sensors_data
    dashboard_env = service_env('dashboard')

    dashboard_env
      .select { |k, _| k.start_with?('INFLUX_SENSOR_') }
      .compact_blank
      .transform_keys { |k| k.delete_prefix('INFLUX_SENSOR_').downcase }
  end

  def reverse_proxy_data
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

  def backup_data
    data = backup_images

    if @reader.services.key?('postgresql-backup')
      data.merge!(
        'enabled' => true,
        'aws_access_key_id' => @reader.raw_env['AWS_ACCESS_KEY_ID'],
        'aws_secret_access_key' => @reader.raw_env['AWS_SECRET_ACCESS_KEY'],
        'aws_region' => @reader.raw_env['AWS_REGION'],
        'aws_bucket' => @reader.raw_env['AWS_BUCKET'],
      )
    end

    data.compact.presence
  end

  def backup_images
    {
      'postgresql' => image_hash_for('postgresql-backup'),
      'influxdb' => image_hash_for('influxdb-backup'),
    }.compact
  end

  def image_hash_for(service_name)
    image = @reader.service(service_name)&.dig('image')
    { 'image' => image } if image
  end
end
