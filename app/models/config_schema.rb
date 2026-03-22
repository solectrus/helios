class ConfigSchema
  # Fields configurable via the setup wizard or system survey
  SYSTEM_FIELDS = %w[
    timezone
    installation_date
    linux_machine
    app_host
    admin_password
    influx_poll_interval
    co2_emission_factor
    force_ssl
    web_concurrency
    frame_ancestors
    ui_theme
    lockup_codeword
    trusted_proxy_ranges
    power_splitter_interval
  ].freeze

  SYSTEM_DEFAULTS = {
    'image' => -> { 'ghcr.io/solectrus/solectrus:latest' },
    'admin_password' => -> { SecureRandom.alphanumeric(32) },
    'secret_key_base' => -> { SecureRandom.hex(64) },
  }.freeze

  SYSTEM_ALL = (SYSTEM_FIELDS + SYSTEM_DEFAULTS.keys).uniq.freeze

  # --- PostgreSQL ---

  POSTGRESQL_DEFAULTS = {
    'image' => -> { 'postgres:18-alpine' },
    'password' => -> { SecureRandom.alphanumeric(32) },
  }.freeze

  POSTGRESQL_ALL = POSTGRESQL_DEFAULTS.keys.freeze

  # --- InfluxDB ---

  INFLUXDB_DEFAULTS = {
    'image' => -> { 'influxdb:2-alpine' },
    'org' => -> { 'solectrus' },
    'bucket' => -> { 'solectrus' },
    'password' => -> { SecureRandom.alphanumeric(32) },
    'token' => -> { SecureRandom.hex(32) },
  }.freeze

  INFLUXDB_ALL = INFLUXDB_DEFAULTS.keys.freeze

  # --- Redis ---

  REDIS_DEFAULTS = {
    'image' => -> { 'redis:8-alpine' },
  }.freeze

  REDIS_ALL = REDIS_DEFAULTS.keys.freeze

  # --- Watchtower ---

  WATCHTOWER_DEFAULTS = {
    'image' => -> { 'nickfedor/watchtower:latest' },
  }.freeze

  WATCHTOWER_ALL = WATCHTOWER_DEFAULTS.keys.freeze

  # --- Backup image defaults ---

  BACKUP_DEFAULTS = {
    'influxdb' => -> { { 'image' => 'ghcr.io/solectrus/influxdb2-s3-backup:latest' } },
    'postgresql' => -> { { 'image' => 'ghcr.io/solectrus/postgres-s3-backup:18' } },
  }.freeze

  # Combined auto-generated defaults keyed by section
  AUTO_GENERATED = {
    'system' => SYSTEM_DEFAULTS,
    'postgresql' => POSTGRESQL_DEFAULTS,
    'influxdb' => INFLUXDB_DEFAULTS,
    'redis' => REDIS_DEFAULTS,
    'watchtower' => WATCHTOWER_DEFAULTS,
    'backup' => BACKUP_DEFAULTS,
  }.freeze

  # --- Source configuration fields ---

  SENEC_FIELDS = %w[
    host schema interval language
    username password totp_uri system_id ignore
    adapter
  ].freeze

  MQTT_FIELDS = %w[
    mqtt_host
    mqtt_port
    mqtt_ssl
    mqtt_username
    mqtt_password
  ].freeze

  SHELLY_FIELDS = %w[
    connection
    interval
  ].freeze

  # --- Per-sensor fields (vary by source) ---

  SENSOR_SHELLY_FIELDS = %w[
    source name shelly_host shelly_password shelly_interval
    shelly_cloud_server shelly_auth_key shelly_device_id
    shelly_invert_power shelly_connection
    exclude_from_house_power
  ].freeze

  SENSOR_MQTT_FIELDS = %w[
    source name mqtt_topic mqtt_payload_type mqtt_json_key mqtt_formula
    exclude_from_house_power
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
    forecast_interval
    forecast_damping_morning
    forecast_damping_evening
    forecast_horizon
    forecast_inverter
    forecast_solar_apikey
    forecast_solcast_api_key
    forecast_solcast_id1
    forecast_solcast_id2
    forecast_pvnode_apikey
    forecast_pvnode_paid
    forecast_pvnode_extra_params
  ].freeze

  REVERSE_PROXY_FIELDS = %w[
    app_domain
    letsencrypt_email
  ].freeze

  BACKUP_FIELDS = %w[
    aws_access_key_id
    aws_secret_access_key
    aws_region
    aws_bucket
  ].freeze

  BACKUP_ALL = (BACKUP_FIELDS + BACKUP_DEFAULTS.keys).uniq.freeze

  # Sensors is a dynamic mapping (sensor_name => config hash),
  # validated via SensorRegistry instead of a fixed field list.
  SENSORS_FIELDS = :dynamic

  # --- Registry ---

  FIELDS = {
    'system' => SYSTEM_ALL,
    'postgresql' => POSTGRESQL_ALL,
    'influxdb' => INFLUXDB_ALL,
    'redis' => REDIS_ALL,
    'watchtower' => WATCHTOWER_ALL,
    'senec' => SENEC_FIELDS,
    'mqtt' => MQTT_FIELDS,
    'shelly' => SHELLY_FIELDS,
    'forecast' => FORECAST_FIELDS,
    'reverse_proxy' => REVERSE_PROXY_FIELDS,
    'backup' => BACKUP_ALL,
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
