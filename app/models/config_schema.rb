class ConfigSchema # rubocop:disable Metrics/ClassLength
  # Fields configurable via the setup wizard or system survey
  SYSTEM_FIELDS = %w[
    timezone
    currency
    installation_date
    app_host
    admin_password
    network_name
    update_interval
  ].freeze

  # Deployment-mode section. The operating mode lives in its own card on the
  # configuration page so the system survey is not split between "what mode
  # do I run" and "general settings".
  DEPLOYMENT_FIELDS = %w[mode].freeze

  # Default Docker network name. Compose's auto-generated default is
  # "<project>_default" with an underscore, so HELIOS sticks with that
  # to stay compatible with vanilla compose installs. Imports preserve
  # any explicit override (e.g. "solectrus-default" with a hyphen) so
  # the regenerated stack does not leave the existing network orphaned.
  DEFAULT_NETWORK_NAME = 'solectrus_default'.freeze

  # Deployment mode: which set of services HELIOS generates.
  #   full             — dashboard, databases, collectors, and supporting services (default)
  #   collectors_only  — only collectors, pushing to an external InfluxDB
  #   dashboard_only   — dashboard, databases, and power-splitter; collectors run remotely
  MODE_FULL = 'full'.freeze
  MODE_COLLECTORS_ONLY = 'collectors_only'.freeze
  MODE_DASHBOARD_ONLY = 'dashboard_only'.freeze
  SYSTEM_MODES = [MODE_FULL, MODE_COLLECTORS_ONLY, MODE_DASHBOARD_ONLY].freeze

  # SECRET_KEY_BASE is seeded by bootstrap/install.sh into .env and promoted
  # into config.yaml on first save. The random fallback keeps tests and
  # one-off boots without an .env from breaking.
  #
  # ADMIN_PASSWORD is derived deterministically from SECRET_KEY_BASE rather
  # than minted from SecureRandom: legacy stacks that pre-date the variable
  # (early-2020 installs, see fixtures/.../real_world/user21) round-trip to
  # the same password every time, instead of churning a new random value
  # into config.yaml on every export. SOLECTRUS' admin actions need *some*
  # password to be usable — without one the dashboard starts but silently
  # blocks editing. bootstrap/install.sh mirrors the same derivation so a
  # real adoption converges on the same value HELIOS would compute.
  SYSTEM_DEFAULTS = {
    'secret_key_base' => -> { ENV['SECRET_KEY_BASE'].presence || SecureRandom.hex(64) },
    'admin_password' => lambda { |context|
      ENV['ADMIN_PASSWORD'].presence ||
        Digest::SHA256.hexdigest(context['secret_key_base'].to_s)[0, 32]
    },
  }.freeze

  SYSTEM_ALL = (SYSTEM_FIELDS + SYSTEM_DEFAULTS.keys).uniq.freeze

  # --- Dashboard ---

  DASHBOARD_DEFAULTS = {
    'image' => DockerImages.current(:DASHBOARD),
  }.freeze

  # Dashboard-specific fields, mostly emitted as Dashboard environment
  # variables. co2_emission_factor, ui_theme and frame_ancestors are set via
  # the dashboard mini-surveys; lockup_codeword and trusted_proxy_ranges are
  # Dashboard env vars stored here too, but surface in the security /
  # reverse-proxy surveys (see Configuration::BORROWED_FIELDS). `host_port`
  # controls the published compose port.
  DASHBOARD_FIELDS = %w[
    co2_emission_factor
    ui_theme
    frame_ancestors
    lockup_codeword
    trusted_proxy_ranges
    host_port
  ].freeze

  DASHBOARD_ALL = (DASHBOARD_FIELDS + DASHBOARD_DEFAULTS.keys).uniq.freeze

  # Optional absolute host path for the service's data directory. When unset,
  # the service uses the default bind mount `./<service>` inside the stack dir.
  # Needed for installations (e.g. Synology) that keep data on a dedicated
  # mount and must not be migrated into the HELIOS-managed stack directory.
  STORAGE_FIELDS = %w[volume_path].freeze

  # --- PostgreSQL ---

  POSTGRESQL_DEFAULTS = {
    'image' => DockerImages.current(:POSTGRESQL),
    'password' => -> { SecureRandom.alphanumeric(32) },
  }.freeze

  # Optional Postgres settings imported verbatim from existing installations.
  # No default, no UI — only persisted when present in the original .env so
  # that re-export does not silently drop a custom setup.
  POSTGRESQL_OPTIONAL_FIELDS = %w[pgdata].freeze

  POSTGRESQL_ALL = (STORAGE_FIELDS + POSTGRESQL_OPTIONAL_FIELDS + POSTGRESQL_DEFAULTS.keys).uniq.freeze

  # --- InfluxDB ---

  # Four roles — admin (init/backup), readwrite (power-splitter), write
  # (collectors), read (dashboard) — kept as distinct fields so a stack with
  # privilege-separated authorizations round-trips losslessly.
  #
  # Note the four lambdas below do NOT yield four different tokens for a stack
  # HELIOS generates itself: Export::Builder#link_influxdb_tokens! collapses
  # them onto one shared value right after resolution, because InfluxDB only
  # lets us dictate the admin token (see the comment there). Distinct values
  # survive only when they came in from an import.
  INFLUXDB_DEFAULTS = {
    'image' => DockerImages.current(:INFLUXDB),
    'org' => 'solectrus',
    'bucket' => 'solectrus',
    'password' => -> { SecureRandom.alphanumeric(32) },
    'token_admin' => -> { SecureRandom.hex(32) },
    'token_readwrite' => -> { SecureRandom.hex(32) },
    'token_write' => -> { SecureRandom.hex(32) },
    'token_read' => -> { SecureRandom.hex(32) },
  }.freeze

  INFLUXDB_TOKEN_FIELDS = %w[token_admin token_readwrite token_write token_read].freeze

  # Fields for targeting an external InfluxDB (used in collectors_only mode).
  INFLUXDB_EXTERNAL_FIELDS = %w[host port schema].freeze

  # Matching .env keys for the external-InfluxDB connection fields.
  INFLUXDB_EXTERNAL_ENV_KEYS = INFLUXDB_EXTERNAL_FIELDS.map { |f| "INFLUX_#{f.upcase}" }.freeze

  # Optional InfluxDB settings imported verbatim from existing installations.
  # No default — only persisted when explicitly set so that re-export does
  # not silently drop or rewrite a custom setup.
  # `publish_port` is captured on import when the imported compose publishes
  # InfluxDB's port 8086 to the host (used for the InfluxDB UI, the HTTP
  # API, and remote tooling/collectors), so re-export does not silently
  # close access a user relies on. Default is to not publish.
  # `host_port` remembers a non-default host-side port mapping (e.g.
  # `18086:8086`) so it survives the round-trip; 8086 is the implicit default
  # and is not persisted.
  INFLUXDB_OPTIONAL_FIELDS = %w[use_hashed_tokens publish_port host_port].freeze

  INFLUXDB_ALL = (
    STORAGE_FIELDS + INFLUXDB_EXTERNAL_FIELDS + INFLUXDB_OPTIONAL_FIELDS + INFLUXDB_DEFAULTS.keys
  ).uniq.freeze

  # --- Redis ---

  REDIS_DEFAULTS = {
    'image' => DockerImages.current(:REDIS),
  }.freeze

  REDIS_ALL = (STORAGE_FIELDS + REDIS_DEFAULTS.keys).uniq.freeze

  # --- Watchtower ---

  # Default WATCHTOWER_POLL_INTERVAL (in seconds) when the user has not
  # picked an interval — keep in sync with surveys/software/survey.json.
  DEFAULT_UPDATE_INTERVAL = '86400'.freeze

  WATCHTOWER_DEFAULTS = {
    'image' => DockerImages.current(:WATCHTOWER),
  }.freeze

  WATCHTOWER_ALL = WATCHTOWER_DEFAULTS.keys.freeze

  # --- Ingest: proxy that recalculates house_power for balcony power plants ---

  INGEST_DEFAULTS = {
    'image' => DockerImages.current(:INGEST),
  }.freeze

  INGEST_FIELDS = %w[retention_hours].freeze

  INGEST_ALL = (STORAGE_FIELDS + INGEST_FIELDS + INGEST_DEFAULTS.keys).uniq.freeze

  # --- HELIOS: the management UI manages its own image channel too ---

  HELIOS_DEFAULTS = {
    'image' => DockerImages.current(:HELIOS),
  }.freeze

  HELIOS_ALL = HELIOS_DEFAULTS.keys.freeze

  # Combined auto-generated defaults keyed by section
  AUTO_GENERATED = {
    'system' => SYSTEM_DEFAULTS,
    'dashboard' => DASHBOARD_DEFAULTS,
    'postgresql' => POSTGRESQL_DEFAULTS,
    'influxdb' => INFLUXDB_DEFAULTS,
    'redis' => REDIS_DEFAULTS,
    'watchtower' => WATCHTOWER_DEFAULTS,
    'ingest' => INGEST_DEFAULTS,
    'helios' => HELIOS_DEFAULTS,
  }.freeze

  # --- Source configuration fields ---

  SENEC_FIELDS = %w[
    host schema interval language
    username password totp_uri system_id request_mode
    adapter version measurement
    image
  ].freeze

  MQTT_FIELDS = %w[
    mqtt_host
    mqtt_port
    mqtt_ssl
    mqtt_username
    mqtt_password
    image
    mappings
  ].freeze

  SHELLY_FIELDS = %w[
    connection
    interval
    cloud_server
    auth_key
    image
    mode
    power_data_type
    password
    devices
  ].freeze

  # --- Per-sensor fields (vary by source) ---

  SENSOR_SHELLY_FIELDS = %w[
    source name shelly_host shelly_password shelly_interval
    shelly_device_id shelly_invert_power shelly_connection
    exclude_from_house_power
  ].freeze

  SENSOR_MQTT_FIELDS = %w[
    source name
    mqtt_topic mqtt_payload_type
    mqtt_json_key mqtt_json_path mqtt_json_formula mqtt_formula
    mqtt_min mqtt_max mqtt_null_to_zero
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
    forecast_pvnode_site_id
    forecast_pvnode_paid
    forecast_pvnode_extra_params
    forecast_pvnode_extra_params1
    forecast_pvnode_extra_params2
    forecast_pvnode_extra_params3
    forecast_pvnode_extra_params4
    forecast_pvnode_azimuth1
    forecast_pvnode_azimuth2
    forecast_pvnode_azimuth3
    forecast_pvnode_azimuth4
    measurement
    image
  ].freeze

  POWER_SPLITTER_FIELDS = %w[image].freeze

  REVERSE_PROXY_FIELDS = (STORAGE_FIELDS + %w[
    mode
    app_domain
    letsencrypt_email
    bind_ip
    image
    command
    ports
    volumes
    restart
    labels
    environment
  ]).uniq.freeze

  BACKUP_FIELDS = %w[
    destination
    external_path
    aws_access_key_id
    aws_secret_access_key
    aws_region
    aws_bucket
    s3_prefix
    s3_endpoint_url
  ].freeze

  BACKUP_ALL = BACKUP_FIELDS

  BACKUP_DESTINATIONS = %w[local external s3].freeze
  BACKUP_DEFAULT_DESTINATION = 'local'.freeze

  # Automatic backup schedule (Issue #106). Lives in its own singleton section
  # so the destination survey on the Backups page and the schedule survey edit
  # independent slices of config.yaml without overwriting each other.
  BACKUP_SCHEDULE_FIELDS = %w[
    schedule_enabled
    schedule_time
  ].freeze

  BACKUP_SCHEDULE_ALL = BACKUP_SCHEDULE_FIELDS

  # Sensors is a dynamic mapping (sensor_name => config hash),
  # validated via SensorRegistry instead of a fixed field list.
  SENSORS_FIELDS = :dynamic

  # Per-service compose-key overrides (ADR-0015). Keyed by managed service
  # name; each value is a hash limited to SERVICE_OVERRIDES_ALLOWED_KEYS.
  # Validated dynamically — see Configuration#sanitize_service_overrides.
  SERVICE_OVERRIDES_FIELDS = :dynamic

  # Compose keys a user may set on a managed service. Deliberately narrow:
  # extending the list requires an ADR amendment. Anything outside is
  # rejected at save time and dropped at import time.
  SERVICE_OVERRIDES_ALLOWED_KEYS = %w[labels ports volumes environment].freeze

  # --- Registry ---

  FIELDS = {
    'system' => SYSTEM_ALL,
    'deployment' => DEPLOYMENT_FIELDS,
    'dashboard' => DASHBOARD_ALL,
    'postgresql' => POSTGRESQL_ALL,
    'influxdb' => INFLUXDB_ALL,
    'redis' => REDIS_ALL,
    'watchtower' => WATCHTOWER_ALL,
    'ingest' => INGEST_ALL,
    'senec' => SENEC_FIELDS,
    'mqtt' => MQTT_FIELDS,
    'shelly' => SHELLY_FIELDS,
    'forecast' => FORECAST_FIELDS,
    'reverse_proxy' => REVERSE_PROXY_FIELDS,
    'backup' => BACKUP_ALL,
    'backup_schedule' => BACKUP_SCHEDULE_ALL,
    'sensors' => SENSORS_FIELDS,
    'power_splitter' => POWER_SPLITTER_FIELDS,
    'helios' => HELIOS_ALL,
    'service_overrides' => SERVICE_OVERRIDES_FIELDS,
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

  # Returns { section => { key => default } } for all missing auto-generated values.
  # Defaults may be plain values or lambdas (used when the value must be lazily
  # generated, e.g. SecureRandom). Use `.resolve_default` to materialize them.
  def self.missing_auto_generated(configuration)
    AUTO_GENERATED.each_with_object({}) do |(section, defaults), result|
      section_data = configuration.respond_to?(section) ? configuration.send(section) : {}
      missing = defaults.reject { |key, _| section_data[key] }
      result[section] = missing unless missing.empty?
    end
  end

  # Materializes a default value: calls lambdas, returns plain values as-is.
  # A 1-arity lambda receives the section's current+already-resolved state
  # (a Hash), so later defaults can derive from earlier ones (e.g.
  # `admin_password` from `secret_key_base`).
  def self.resolve_default(value, context = nil)
    return value unless value.respond_to?(:call)

    value.arity.zero? ? value.call : value.call(context)
  end
end
