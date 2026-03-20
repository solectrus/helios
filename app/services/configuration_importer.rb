class ConfigurationImporter # rubocop:disable Metrics/ClassLength
  # Dashboard defaults that are always set in compose.yaml regardless of config.
  # Only store values that differ from these defaults.
  DASHBOARD_DEFAULTS = {
    'INFLUX_POLL_INTERVAL' => '5',
    'WEB_CONCURRENCY' => '0',
  }.freeze

  # All service names that Helios manages (generates in compose.yaml)
  MANAGED_SERVICES = %w[
    dashboard postgresql redis influxdb watchtower helios
    traefik postgresql-backup influxdb-backup
    senec-collector shelly-collector mqtt-collector forecast-collector power-splitter
  ].freeze

  # All .env variable keys that Helios manages (generates in .env)
  MANAGED_ENV_KEYS = %w[
    TZ INSTALLATION_DATE ADMIN_PASSWORD SECRET_KEY_BASE
    APP_HOST INFLUX_POLL_INTERVAL CO2_EMISSION_FACTOR
    FORCE_SSL WEB_CONCURRENCY FRAME_ANCESTORS UI_THEME
    INFLUX_EXCLUDE_FROM_HOUSE_POWER
    LOCKUP_CODEWORD TRUSTED_PROXY_RANGES
    POWER_SPLITTER_INTERVAL
    POSTGRES_PASSWORD
    INFLUX_PASSWORD INFLUX_ORG INFLUX_BUCKET INFLUX_TOKEN
    INFLUX_ADMIN_TOKEN INFLUX_TOKEN_READ INFLUX_TOKEN_WRITE
    INFLUX_MEASUREMENT INFLUX_MEASUREMENT_SENEC INFLUX_MEASUREMENT_FORECAST
    INFLUX_MEASUREMENT_SHELLY INFLUX_MEASUREMENT_MQTT
    INFLUX_MODE INFLUX_POWER_DATA_TYPE
    HELIOS_HOST_STACK_PATH
    APP_DOMAIN LETSENCRYPT_EMAIL
    AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_REGION AWS_BUCKET
    SENEC_ADAPTER SENEC_HOST SENEC_SCHEMA SENEC_LANGUAGE SENEC_INTERVAL
    SENEC_USERNAME SENEC_PASSWORD SENEC_TOTP_URI SENEC_SYSTEM_ID SENEC_IGNORE
    FORECAST_PROVIDER FORECAST_LATITUDE FORECAST_LONGITUDE
    FORECAST_DECLINATION FORECAST_AZIMUTH FORECAST_KWP
    FORECAST_CONFIGURATIONS FORECAST_INTERVAL
    FORECAST_DAMPING_MORNING FORECAST_DAMPING_EVENING
    FORECAST_HORIZON FORECAST_INVERTER
    FORECAST_SOLAR_APIKEY SOLCAST_APIKEY SOLCAST_SITE
    PVNODE_APIKEY PVNODE_PAID PVNODE_EXTRA_PARAMS
    SHELLY_HOST SHELLY_INTERVAL SHELLY_PASSWORD
    SHELLY_CLOUD_SERVER SHELLY_AUTH_KEY SHELLY_DEVICE_ID SHELLY_INVERT_POWER
    MQTT_HOST MQTT_PORT MQTT_SSL MQTT_USERNAME MQTT_PASSWORD
  ].freeze

  # Infrastructure .env keys that Helios doesn't generate but are well-known
  # SOLECTRUS vars. These are suppressed from unmanaged to avoid noise.
  INFRASTRUCTURE_ENV_KEYS = %w[
    INFLUX_HOST INFLUX_SCHEMA INFLUX_PORT INFLUX_VOLUME_PATH INFLUX_USERNAME
    DB_HOST DB_USER DB_PASSWORD DB_VOLUME_PATH DB_DATABASE
    REDIS_URL REDIS_VOLUME_PATH
  ].freeze

  # Maps device type to the field name that holds the data source identifier
  DATA_SOURCE_FIELDS = {
    'inverter' => 'battery_vendor',
    'wallbox' => 'wallbox_vendor',
    'heatpump' => 'heatpump_access',
  }.freeze

  MQTT_MAPPING_FIELDS = %i[
    topic measurement field json_key json_path json_formula
    measurement_positive measurement_negative field_positive field_negative
    type min max null_to_zero
  ].freeze

  SHELLY_OPTIONAL_FIELDS = {
    passwords: 'shelly_password',
    cloud_servers: 'shelly_cloud_server',
    auth_keys: 'shelly_auth_key',
    device_ids: 'shelly_device_id',
    invert_powers: 'shelly_invert_power',
  }.freeze

  # Maps sensor names to the device type they indicate.
  # Sensors not listed here are either shared (forecast)
  # or handled via pattern matching (inverter_power_*, custom_power_*).
  SENSOR_DEVICE_TYPE = {
    'wallbox_power' => 'wallbox',
    'wallbox_car_connected' => 'wallbox',
    'car_battery_soc' => 'car',
    'heatpump_power' => 'heatpump',
    'heatpump_heating_power' => 'heatpump',
    'heatpump_status' => 'heatpump',
    'heatpump_tank_temp' => 'heatpump',
    'battery_soc' => 'battery',
    'battery_charging_power' => 'battery',
    'battery_discharging_power' => 'battery',
    'case_temp' => 'inverter',
    'system_status' => 'inverter',
    'system_status_ok' => 'inverter',
    'grid_export_limit' => 'inverter',
    'house_power' => 'inverter',
    'grid_import_power' => 'inverter',
    'grid_export_power' => 'inverter',
    'outdoor_temp' => 'inverter',
  }.freeze

  # Maps sensor names to the mqtt_topic_* field they should be stored in.
  # The primary sensor for each device type maps to plain 'mqtt_topic'.
  SENSOR_TOPIC_FIELDS = {
    'heatpump_power' => 'mqtt_topic',
    'heatpump_heating_power' => 'mqtt_topic_heating_power',
    'heatpump_tank_temp' => 'mqtt_topic_tank_temp',
    'heatpump_status' => 'mqtt_topic_heatpump_status',
    'outdoor_temp' => 'mqtt_topic_outdoor_temp',
    'wallbox_power' => 'mqtt_topic',
    'wallbox_car_connected' => 'mqtt_topic_car_connected',
    'car_battery_soc' => 'mqtt_topic',
  }.freeze

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
    persist_sensors_from_devices!(config)
    persist_unmanaged!(config)

    config
  end

  private

  def build_result # rubocop:disable Metrics/MethodLength
    {
      system: system_data,
      postgresql: postgresql_data,
      influxdb: influxdb_data,
      redis: redis_data,
      watchtower: watchtower_data,
      sensors: sensors_data,
      forecast: forecast_data,
      senec: senec_data,
      mqtt: mqtt_broker_data,
      shelly: shelly_section_data,
      reverse_proxy: reverse_proxy_data,
      backup: backup_data,
      devices: build_devices,
      unmanaged: unmanaged_data,
    }
  end

  def build_devices
    devices = []
    devices << senec_device_data if senec_collector?
    devices.concat(shelly_device_data) if shelly_collector?
    devices.concat(mqtt_device_data) if mqtt_collector?
    distribute_house_power_exclusions(devices)
    devices
  end

  def persist_singletons!(config)
    %i[system postgresql influxdb redis watchtower sensors forecast senec mqtt shelly reverse_proxy
       backup].each do |key|
      config.update(key.to_s, result[key]) if result[key]
    end
  end

  def persist_sensors_from_devices!(config)
    # Convert device-based import to sensor-centric config
    sensors = result[:sensors] || {}
    devices = result[:devices] || []

    # For each sensor mapping, determine source from devices
    sensors.each_key do |sensor_name|
      source = infer_source_for_sensor(sensor_name, devices)
      next unless source

      sensor_data = build_sensor_data(sensor_name, source, devices)
      config.update_sensor(sensor_name, sensor_data)
    end
  end

  def infer_source_for_sensor(sensor_name, devices)
    return 'senec' if SensorMappings::SENEC_DEFAULTS.key?(sensor_name) && senec_collector?
    return 'forecast' if SensorMappings::FORECAST_DEFAULTS.key?(sensor_name)
    return 'shelly' if device_provides_sensor?(devices, sensor_name, 'shelly')
    return 'mqtt' if device_provides_sensor?(devices, sensor_name, 'mqtt')

    'smart_home'
  end

  def device_provides_sensor?(devices, sensor_name, source_type)
    source_fields = %w[data_source wallbox_vendor heatpump_access battery_vendor]

    devices.any? do |device|
      next unless device[:data].values_at(*source_fields).include?(source_type)

      sensor_mapping = result[:sensors][sensor_name]
      next unless sensor_mapping

      sensor_mapping.start_with?("#{device[:name]}:")
    end
  end

  def build_sensor_data(sensor_name, source, devices)
    data = { 'source' => source }

    case source
    when 'senec' then merge_senec_sensor_overrides!(data, sensor_name)
    when 'forecast' then merge_forecast_sensor_overrides!(data, sensor_name)
    when 'shelly' then merge_shelly_sensor_data!(data, sensor_name, devices)
    when 'mqtt' then merge_mqtt_sensor_data!(data, sensor_name)
    end

    data.compact
  end

  def merge_senec_sensor_overrides!(data, sensor_name)
    merge_sensor_overrides!(data, sensor_name, SensorMappings::SENEC_DEFAULTS)
  end

  def merge_forecast_sensor_overrides!(data, sensor_name)
    merge_sensor_overrides!(data, sensor_name, SensorMappings::FORECAST_DEFAULTS)
  end

  def merge_sensor_overrides!(data, sensor_name, defaults_hash)
    mapping = result[:sensors][sensor_name]
    return unless mapping

    defaults = defaults_hash[sensor_name]
    return unless defaults

    measurement, field = mapping.split(':', 2)
    default_mapping = "#{defaults[:measurement]}:#{defaults[:field]}"
    return if mapping == default_mapping

    data['measurement'] = measurement
    data['field'] = field
  end

  def merge_shelly_sensor_data!(data, sensor_name, devices)
    device = find_shelly_device_for_sensor(sensor_name, devices)
    return unless device

    merge_shelly_mapping!(data, sensor_name)
    merge_shelly_device_fields!(data, device)
  end

  def merge_shelly_mapping!(data, sensor_name)
    mapping = result[:sensors][sensor_name]
    return unless mapping

    measurement, field = mapping.split(':', 2)
    data['measurement'] = measurement
    data['field'] = field
  end

  def merge_shelly_device_fields!(data, device)
    device_data = device[:data]
    data['name'] = device_data['name'] || device[:name]
    data['shelly_connection'] = infer_shelly_connection(device_data)
    data['shelly_host'] = device_data['shelly_host']
    data['shelly_interval'] = device_data['shelly_interval']
    data['shelly_password'] = device_data['shelly_password']
    data['exclude_from_house_power'] = true if device_data['exclude_from_house_power']
  end

  def infer_shelly_connection(device_data)
    device_data['shelly_cloud_server'].present? ? 'cloud' : 'local'
  end

  def merge_mqtt_sensor_data!(data, sensor_name)
    details = mqtt_mapping_details[sensor_name]
    return unless details

    data.merge!(details)
  end

  # Build a per-sensor lookup of MQTT mapping details from the mqtt-collector env
  def mqtt_mapping_details
    @mqtt_mapping_details ||= build_mqtt_mapping_details
  end

  def build_mqtt_mapping_details
    return {} unless mqtt_collector?

    mqtt_mappings.each_with_object({}) do |mapping, details|
      sensor_name = find_sensor_for_mqtt_mapping(mapping)
      next unless sensor_name

      details[sensor_name] = mqtt_mapping_to_sensor_data(mapping)
    end
  end

  def find_sensor_for_mqtt_mapping(mapping)
    candidate = "#{mapping[:measurement]}:#{mapping[:field]}"
    find_sensor_for_candidate(sensors_data, candidate)
  end

  def mqtt_mapping_to_sensor_data(mapping)
    {
      'measurement' => mapping[:measurement],
      'field' => mapping[:field],
      'mqtt_topic' => mapping[:topic],
      'mqtt_payload_type' => mapping[:type],
      'mqtt_json_key' => mapping[:json_key],
      'mqtt_formula' => mapping[:json_formula],
    }.compact
  end

  def find_shelly_device_for_sensor(sensor_name, devices)
    mapping = result[:sensors][sensor_name]
    return nil unless mapping

    devices.find do |device|
      data = device[:data]
      is_shelly = data.values_at('data_source', 'wallbox_vendor', 'heatpump_access',
                                 'battery_vendor').include?('shelly')
      is_shelly && mapping.start_with?("#{device[:name]}:")
    end
  end

  def persist_unmanaged!(config)
    unmanaged = result[:unmanaged]
    config.update_unmanaged(unmanaged) if unmanaged.present?
  end

  # Environment of a specific service (memoized per service name)
  def service_env(name)
    @service_envs ||= {}
    @service_envs[name] ||= @reader.service(name)&.dig('environment') || {}
  end

  def system_data
    system_core_data
      .merge(system_dashboard_data)
      .merge('power_splitter_interval' => power_splitter_interval)
      .compact
  end

  def system_core_data
    dashboard_env = service_env('dashboard')

    {
      'timezone' => dashboard_env['TZ'],
      'installation_date' => dashboard_env['INSTALLATION_DATE'],
      'image' => @reader.service('dashboard')&.dig('image'),
      'admin_password' => @reader.raw_env['ADMIN_PASSWORD'],
      'secret_key_base' => @reader.raw_env['SECRET_KEY_BASE'],
    }
  end

  def system_dashboard_data
    dashboard_env = service_env('dashboard')

    system_optional_dashboard_data(dashboard_env)
      .merge(system_non_default_dashboard_data(dashboard_env))
  end

  def system_optional_dashboard_data(dashboard_env)
    {
      'app_host' => dashboard_env['APP_HOST'],
      'co2_emission_factor' => dashboard_env['CO2_EMISSION_FACTOR'],
      'force_ssl' => dashboard_env['FORCE_SSL'],
      'frame_ancestors' => dashboard_env['FRAME_ANCESTORS'],
      'ui_theme' => dashboard_env['UI_THEME'],
      'lockup_codeword' => dashboard_env['LOCKUP_CODEWORD'],
      'trusted_proxy_ranges' => dashboard_env['TRUSTED_PROXY_RANGES'],
    }
  end

  def system_non_default_dashboard_data(dashboard_env)
    DASHBOARD_DEFAULTS.each_with_object({}) do |(env_key, default), data|
      value = dashboard_env[env_key]
      data[env_key.downcase] = value if value.present? && value.to_s != default
    end
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
    # Support token aliasing: prefer INFLUX_TOKEN, fallback to INFLUX_ADMIN_TOKEN or INFLUX_TOKEN_WRITE
    token = @reader.raw_env['INFLUX_TOKEN'].presence ||
            @reader.raw_env['INFLUX_ADMIN_TOKEN'].presence ||
            @reader.raw_env['INFLUX_TOKEN_WRITE']

    {
      'image' => @reader.service('influxdb')&.dig('image'),
      'password' => @reader.raw_env['INFLUX_PASSWORD'],
      'org' => @reader.raw_env['INFLUX_ORG'],
      'bucket' => @reader.raw_env['INFLUX_BUCKET'],
      'token' => token,
    }.compact
  end

  # --- SENEC ---

  def senec_collector?
    @reader.services.key?('senec-collector')
  end

  def senec_data
    return unless senec_collector?

    senec_env = service_env('senec-collector')
    data = {
      'adapter' => senec_env['SENEC_ADAPTER'] || 'local',
      'interval' => senec_env['SENEC_INTERVAL'],
      'ignore' => senec_env['SENEC_IGNORE'],
    }

    if senec_env['SENEC_ADAPTER'] == 'cloud'
      data.merge!('username' => senec_env['SENEC_USERNAME'], 'password' => senec_env['SENEC_PASSWORD'],
                  'totp_uri' => senec_env['SENEC_TOTP_URI'], 'system_id' => senec_env['SENEC_SYSTEM_ID'])
    else
      data.merge!('host' => senec_env['SENEC_HOST'], 'schema' => senec_env['SENEC_SCHEMA'],
                  'language' => senec_env['SENEC_LANGUAGE'])
    end

    data.compact.presence
  end

  def senec_device_data
    senec_env = service_env('senec-collector')

    data =
      { 'battery_vendor' => senec_vendor(senec_env) }
      .merge(senec_env['SENEC_ADAPTER'] == 'cloud' ? senec_cloud_settings(senec_env) : senec_local_settings(senec_env))
      .merge('senec_interval' => senec_env['SENEC_INTERVAL'])
      .merge('senec_ignore' => senec_env['SENEC_IGNORE'])
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

  # --- Shelly ---

  def shelly_collector?
    @reader.services.key?('shelly-collector')
  end

  def shelly_section_data
    return unless shelly_collector?

    shelly_env = service_env('shelly-collector')
    connection = shelly_env['SHELLY_CLOUD_SERVER'].present? ? 'cloud' : 'local'
    intervals = csv_split(shelly_env['SHELLY_INTERVAL'])
    interval = intervals.first.presence || '5'

    {
      'connection' => connection,
      'interval' => interval,
    }
  end

  def shelly_device_data
    parsed = parse_shelly_csv_fields
    build_shelly_devices(parsed)
  end

  def parse_shelly_csv_fields
    shelly_env = service_env('shelly-collector')
    {
      hosts: csv_split(shelly_env['SHELLY_HOST']),
      intervals: csv_split(shelly_env['SHELLY_INTERVAL']),
      measurements: csv_split(shelly_env['INFLUX_MEASUREMENT']),
      passwords: csv_split(shelly_env['SHELLY_PASSWORD']),
      cloud_servers: csv_split(shelly_env['SHELLY_CLOUD_SERVER']),
      auth_keys: csv_split(shelly_env['SHELLY_AUTH_KEY']),
      device_ids: csv_split(shelly_env['SHELLY_DEVICE_ID']),
      invert_powers: csv_split(shelly_env['SHELLY_INVERT_POWER']),
    }
  end

  def build_shelly_devices(parsed)
    parsed[:hosts].each_with_index.filter_map do |host, i|
      next if host.blank?

      build_single_shelly_device(host, i, parsed)
    end
  end

  def build_single_shelly_device(_host, index, parsed)
    name = parsed[:measurements][index].presence || "Shelly#{index + 1}"
    device_type = infer_shelly_device_type(name)
    data = shelly_device_config(device_type, index, parsed)

    { type: device_type, name:, data: }
  end

  def shelly_device_config(device_type, index, parsed)
    field = DATA_SOURCE_FIELDS.fetch(device_type, 'data_source')
    data = {
      field => 'shelly',
      'shelly_host' => parsed[:hosts][index],
      'shelly_interval' => parsed[:intervals][index].presence || '5',
    }
    shelly_optional_fields(data, index, parsed)
    data
  end

  def shelly_optional_fields(data, index, parsed)
    SHELLY_OPTIONAL_FIELDS.each do |key, field|
      value = parsed[key][index]
      data[field] = value if value.present?
    end
  end

  def csv_split(value)
    value.to_s.split(',').map(&:strip)
  end

  def infer_shelly_device_type(measurement_name)
    mapping = "#{measurement_name}:power"
    sensors = sensors_data
    return 'inverter' if inverter_sensor?(sensors, mapping)
    return 'heatpump' if sensors['heatpump_power'] == mapping
    return 'wallbox' if sensors['wallbox_power'] == mapping

    'consumer'
  end

  def inverter_sensor?(sensors, mapping)
    %w[inverter_power inverter_power_1 inverter_power_2
       inverter_power_3 inverter_power_4 inverter_power_5].any? do |key|
      sensors[key] == mapping
    end
  end

  # --- Forecast ---

  def forecast_collector?
    @reader.services.key?('forecast-collector')
  end

  def forecast_data
    return unless forecast_collector?

    fc_env = service_env('forecast-collector')
    data = forecast_base_data(fc_env)
    data.merge!(forecast_roof_data(fc_env))
    data.merge!(forecast_provider_data(fc_env))
    data.compact.presence
  end

  def forecast_base_data(fc_env)
    {
      'forecast' => fc_env['FORECAST_PROVIDER'],
      'forecast_latitude' => fc_env['FORECAST_LATITUDE'],
      'forecast_longitude' => fc_env['FORECAST_LONGITUDE'],
      'forecast_interval' => fc_env['FORECAST_INTERVAL'],
      'forecast_damping_morning' => fc_env['FORECAST_DAMPING_MORNING'],
      'forecast_damping_evening' => fc_env['FORECAST_DAMPING_EVENING'],
      'forecast_horizon' => fc_env['FORECAST_HORIZON'],
      'forecast_inverter' => fc_env['FORECAST_INVERTER'],
    }
  end

  def forecast_roof_data(fc_env)
    configs = fc_env['FORECAST_CONFIGURATIONS']&.to_i
    return forecast_single_roof_data(fc_env) unless configs && configs > 1

    forecast_multi_roof_data(fc_env, configs)
  end

  def forecast_single_roof_data(fc_env)
    {
      'forecast_roofs' => '1',
      'forecast_declination1' => fc_env['FORECAST_DECLINATION'],
      'forecast_azimuth1' => fc_env['FORECAST_AZIMUTH'],
      'forecast_kwp1' => fc_env['FORECAST_KWP'],
    }
  end

  def forecast_multi_roof_data(fc_env, configs)
    data = { 'forecast_roofs' => configs.to_s }
    configs.times do |i|
      data["forecast_declination#{i + 1}"] = fc_env["FORECAST_#{i}_DECLINATION"]
      data["forecast_azimuth#{i + 1}"] = fc_env["FORECAST_#{i}_AZIMUTH"]
      data["forecast_kwp#{i + 1}"] = fc_env["FORECAST_#{i}_KWP"]
    end
    data
  end

  def forecast_provider_data(fc_env) # rubocop:disable Metrics/MethodLength
    case fc_env['FORECAST_PROVIDER']
    when 'forecast.solar'
      { 'forecast_solar_apikey' => fc_env['FORECAST_SOLAR_APIKEY'] }
    when 'solcast'
      {
        'forecast_solcast_api_key' => fc_env['SOLCAST_APIKEY'],
        'forecast_solcast_id1' => fc_env['SOLCAST_SITE'] || fc_env['SOLCAST_0_SITE'],
        'forecast_solcast_id2' => fc_env['SOLCAST_1_SITE'],
      }
    when 'pvnode'
      {
        'forecast_pvnode_apikey' => fc_env['PVNODE_APIKEY'],
        'forecast_pvnode_paid' => fc_env['PVNODE_PAID'],
        'forecast_pvnode_extra_params' => fc_env['PVNODE_EXTRA_PARAMS'],
      }
    else
      {}
    end
  end

  # --- Sensors ---

  def sensors_data
    @sensors_data ||= begin
      dashboard_env = service_env('dashboard')
      dashboard_env
        .select { |k, _| k.start_with?('INFLUX_SENSOR_') }
        .compact_blank
        .transform_keys { |k| k.delete_prefix('INFLUX_SENSOR_').downcase }
    end
  end

  # --- Reverse Proxy ---

  def reverse_proxy_data
    return unless @reader.services.key?('traefik')

    domain = extract_domain_from_dashboard_labels
    return unless domain

    {
      'app_domain' => domain,
      'letsencrypt_email' => @reader.raw_env['LETSENCRYPT_EMAIL'],
    }.compact
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

  # --- House power exclusions ---

  def distribute_house_power_exclusions(devices)
    excluded = excluded_sensor_names
    return if excluded.empty?

    consumer_index = 0
    devices.each do |device|
      sensor = sensor_name_for_device(device, consumer_index)
      consumer_index += 1 if device[:type] == 'consumer'
      next unless sensor

      device[:data]['exclude_from_house_power'] = true if excluded.include?(sensor.upcase)
    end
  end

  def excluded_sensor_names
    dashboard_env = service_env('dashboard')
    value = dashboard_env['INFLUX_EXCLUDE_FROM_HOUSE_POWER']
    return [] if value.blank?

    csv_split(value)
  end

  def sensor_name_for_device(device, consumer_index)
    case device[:type]
    when 'heatpump' then 'HEATPUMP_POWER'
    when 'wallbox' then 'WALLBOX_POWER'
    when 'consumer' then format('CUSTOM_POWER_%02d', consumer_index + 1)
    end
  end

  # --- Backup ---

  def backup_data
    return unless @reader.services.key?('postgresql-backup')

    {
      'postgresql' => image_hash_for('postgresql-backup'),
      'influxdb' => image_hash_for('influxdb-backup'),
      'aws_access_key_id' => @reader.raw_env['AWS_ACCESS_KEY_ID'],
      'aws_secret_access_key' => @reader.raw_env['AWS_SECRET_ACCESS_KEY'],
      'aws_region' => @reader.raw_env['AWS_REGION'],
      'aws_bucket' => @reader.raw_env['AWS_BUCKET'],
    }.compact
  end

  def image_hash_for(service_name)
    image = @reader.service(service_name)&.dig('image')
    { 'image' => image } if image
  end

  # --- Power-Splitter ---

  def power_splitter_interval
    ps_env = service_env('power-splitter')
    ps_env['POWER_SPLITTER_INTERVAL']
  end

  # --- MQTT ---

  def mqtt_collector?
    @reader.services.key?('mqtt-collector')
  end

  def mqtt_broker_data
    return unless mqtt_collector?

    mqtt_env = service_env('mqtt-collector')
    {
      'mqtt_host' => mqtt_env['MQTT_HOST'],
      'mqtt_port' => mqtt_env['MQTT_PORT'],
      'mqtt_ssl' => mqtt_env['MQTT_SSL'],
      'mqtt_username' => mqtt_env['MQTT_USERNAME'],
      'mqtt_password' => mqtt_env['MQTT_PASSWORD'],
    }.compact.presence
  end

  def mqtt_device_data
    build_mqtt_devices(mqtt_mappings)
  end

  def mqtt_mappings
    @mqtt_mappings ||= parse_mqtt_mappings(service_env('mqtt-collector'))
  end

  def parse_mqtt_mappings(mqtt_env)
    mqtt_mapping_indices(mqtt_env).map do |i|
      MQTT_MAPPING_FIELDS.index_with { |f| mqtt_env["MAPPING_#{i}_#{f.upcase}"] }.compact
    end
  end

  def mqtt_mapping_indices(mqtt_env)
    mqtt_env.keys
            .filter_map { |k| k[/\AMAPPING_(\d+)_/, 1]&.to_i }
            .uniq
            .sort
  end

  def build_mqtt_devices(mappings)
    # Group mappings by measurement name (one measurement = one device)
    grouped = mappings.group_by { |m| m[:measurement].presence }
    grouped.delete(nil) # skip mappings without measurement

    grouped.filter_map do |measurement, device_mappings|
      device_type = infer_mqtt_device_type(measurement, device_mappings)
      next unless device_type

      field = DATA_SOURCE_FIELDS.fetch(device_type, 'data_source')
      data = { field => 'mqtt' }
      assign_mqtt_topics(data, measurement, device_mappings)

      { type: device_type, name: measurement, data: }
    end
  end

  def assign_mqtt_topics(data, measurement, device_mappings)
    sensors = sensors_data

    device_mappings.each do |mapping|
      topic = mapping[:topic]
      next if topic.blank?

      candidate = "#{measurement}:#{mapping[:field]}"
      sensor_name = find_sensor_for_candidate(sensors, candidate)
      topic_field = sensor_name ? SENSOR_TOPIC_FIELDS[sensor_name] : nil

      # Use specific topic field if known, otherwise set generic mqtt_topic
      data[topic_field || 'mqtt_topic'] ||= topic
    end
  end

  def find_sensor_for_candidate(sensors, candidate)
    sensors.find { |_, value| value == candidate }&.first
  end

  def infer_mqtt_device_type(measurement, device_mappings)
    sensors = sensors_data

    device_mappings.each do |mapping|
      candidate = "#{measurement}:#{mapping[:field]}"
      type = find_device_type_for_candidate(sensors, candidate)
      return type if type
    end

    # Fallback: consumer
    'consumer'
  end

  def find_device_type_for_candidate(sensors, candidate)
    sensors.each do |sensor_name, sensor_value|
      next unless sensor_value == candidate

      # Inverter power sensors (inverter_power, inverter_power_1..5)
      return 'inverter' if sensor_name.match?(/\Ainverter_power(_\d)?\z/)

      # Custom power sensors → consumer
      return 'consumer' if sensor_name.match?(/\Acustom_power_\d{2}\z/)

      # Direct lookup for all other sensors
      return SENSOR_DEVICE_TYPE[sensor_name] if SENSOR_DEVICE_TYPE.key?(sensor_name)
    end

    nil
  end

  # --- Unmanaged ---

  def unmanaged_data
    data = {}

    unmanaged_services = detect_unmanaged_services
    data['services'] = unmanaged_services if unmanaged_services.present?

    unmanaged_env = detect_unmanaged_env_vars
    data['env_vars'] = unmanaged_env if unmanaged_env.present?

    data.presence
  end

  def detect_unmanaged_services
    raw_services = @reader.raw_compose['services'] || {}
    raw_services.except(*MANAGED_SERVICES).presence
  end

  def detect_unmanaged_env_vars
    all_managed = all_managed_env_keys
    @reader.raw_env.to_h.except(*all_managed).presence
  end

  def all_managed_env_keys
    MANAGED_ENV_KEYS +
      INFRASTRUCTURE_ENV_KEYS +
      SensorRegistry::SENSORS.keys.map { |s| "INFLUX_SENSOR_#{s.upcase}" } +
      forecast_indexed_env_keys +
      pvnode_indexed_env_keys +
      mqtt_mapping_env_keys
  end

  def forecast_indexed_env_keys
    (0..3).flat_map do |i|
      ["FORECAST_#{i}_DECLINATION", "FORECAST_#{i}_AZIMUTH", "FORECAST_#{i}_KWP", "SOLCAST_#{i}_SITE"]
    end
  end

  def pvnode_indexed_env_keys
    (0..3).map { |i| "PVNODE_#{i}_EXTRA_PARAMS" }
  end

  def mqtt_mapping_env_keys
    # Detect all MAPPING_N_* keys from the raw .env
    @reader.raw_env.to_h.keys.grep(/\AMAPPING_\d+_/)
  end
end
