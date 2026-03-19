class ConfigSchema
  # Fields configurable via the setup wizard or system survey
  SYSTEM_FIELDS = %w[
    timezone
    installation_date
    linux_machine
    app_host
    app_port
    admin_password
    secret_key_base
  ].freeze

  # Auto-generated defaults for system fields
  SYSTEM_DEFAULTS = {
    'admin_password' => -> { SecureRandom.alphanumeric(32) },
    'secret_key_base' => -> { SecureRandom.hex(64) },
  }.freeze

  # Optional Docker image overrides (set by importer, not by surveys)
  SYSTEM_IMAGE_OVERRIDES = %w[
    dashboard_image
    postgresql_image
    redis_image
    influxdb_image
    influxdb_backup_image
    helios_image
    watchtower_image
  ].freeze

  # All valid system fields
  SYSTEM_ALL = (SYSTEM_FIELDS + SYSTEM_IMAGE_OVERRIDES).freeze

  # --- PostgreSQL ---

  POSTGRESQL_DEFAULTS = {
    'password' => -> { SecureRandom.alphanumeric(32) },
  }.freeze

  POSTGRESQL_ALL = POSTGRESQL_DEFAULTS.keys.freeze

  # --- InfluxDB ---

  INFLUXDB_DEFAULTS = {
    'org' => -> { 'solectrus' },
    'bucket' => -> { 'solectrus' },
    'password' => -> { SecureRandom.alphanumeric(32) },
    'token' => -> { SecureRandom.hex(32) },
  }.freeze

  INFLUXDB_ALL = INFLUXDB_DEFAULTS.keys.freeze

  # Combined auto-generated defaults keyed by section
  AUTO_GENERATED = {
    'system' => SYSTEM_DEFAULTS,
    'postgresql' => POSTGRESQL_DEFAULTS,
    'influxdb' => INFLUXDB_DEFAULTS,
  }.freeze

  # --- Device fields ---

  INVERTER_FIELDS = %w[
    battery_vendor
    house_power_known
    senec_host
    senec_interval
    senec_schema
    senec_language
    senec_username
    senec_password
    senec_totp_uri
    senec_system_id
    smart_home_system
  ].freeze

  BATTERY_FIELDS = %w[
    data_source
    smart_home_system
  ].freeze

  WALLBOX_FIELDS = %w[
    wallbox_vendor
    shelly_host
    shelly_interval
    shelly_password
    smart_home_system
    mqtt_topic
  ].freeze

  CAR_FIELDS = %w[
    data_source
    smart_home_system
    mqtt_topic
  ].freeze

  HEATPUMP_FIELDS = %w[
    heatpump_access
    shelly_host
    shelly_interval
    shelly_password
    smart_home_system
    mqtt_topic
  ].freeze

  CONSUMER_FIELDS = %w[
    data_source
    shelly_host
    shelly_interval
    shelly_password
    smart_home_system
    mqtt_topic
  ].freeze

  # --- Singleton fields ---

  FORECAST_FIELDS = %w[
    forecast
    forecast_roofs
    forecast_latitude
    forecast_longitude
    forecast_azimuth1
    forecast_declination1
    forecast_kwp1
    forecast_azimuth2
    forecast_declination2
    forecast_kwp2
    forecast_azimuth3
    forecast_declination3
    forecast_kwp3
    forecast_azimuth4
    forecast_declination4
    forecast_kwp4
    forecast_solcast_api_key
    forecast_solcast_id1
    forecast_solcast_id2
  ].freeze

  REVERSE_PROXY_FIELDS = %w[
    enabled
    app_domain
  ].freeze

  BACKUP_FIELDS = %w[
    enabled
    aws_access_key_id
    aws_secret_access_key
    aws_region
    aws_bucket
  ].freeze

  # Sensors is a dynamic mapping (sensor_name => influx_field),
  # validated via SensorRegistry instead of a fixed field list.
  SENSORS_FIELDS = :dynamic

  # --- Registry ---

  FIELDS = {
    'system' => SYSTEM_ALL,
    'postgresql' => POSTGRESQL_ALL,
    'influxdb' => INFLUXDB_ALL,
    'inverter' => INVERTER_FIELDS,
    'battery' => BATTERY_FIELDS,
    'wallbox' => WALLBOX_FIELDS,
    'car' => CAR_FIELDS,
    'heatpump' => HEATPUMP_FIELDS,
    'consumer' => CONSUMER_FIELDS,
    'forecast' => FORECAST_FIELDS,
    'reverse_proxy' => REVERSE_PROXY_FIELDS,
    'backup' => BACKUP_FIELDS,
    'sensors' => SENSORS_FIELDS,
  }.freeze

  def self.fields_for(setting)
    FIELDS[setting.to_s]
  end

  def self.valid_field?(setting, field)
    fields = fields_for(setting)
    return true if fields == :dynamic
    return false unless fields

    field.to_s.in?(fields)
  end

  # Returns { section => { key => lambda } } for all missing auto-generated values
  def self.missing_auto_generated(configuration)
    AUTO_GENERATED.each_with_object({}) do |(section, defaults), result|
      section_data = configuration.respond_to?(section) ? configuration.send(section) : {}
      missing = defaults.reject { |key, _| section_data[key] }
      result[section] = missing unless missing.empty?
    end
  end
end
