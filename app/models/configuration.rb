class Configuration # rubocop:disable Metrics/ClassLength
  YAML_FILENAME = 'config.yaml'.freeze

  # Singletons exist at most once per configuration
  SINGLETONS = %w[
    deployment system dashboard postgresql influxdb redis
    watchtower forecast senec mqtt tibber senec_charger shelly reverse_proxy
    backup backup_schedule sensors ingest power_splitter
    helios service_overrides
  ].freeze

  # Sections hidden from the configuration UI (auto-managed). Ingest is not
  # listed: it has user-facing knobs (image, retention_hours) and is surfaced
  # via #visible_settings whenever a balcony sensor activates it.
  # `senec_charger` has no survey of its own: the prices survey configures it
  # alongside the Tibber collector (see BORROWED_FIELDS).
  HIDDEN = %w[postgresql redis watchtower power_splitter senec_charger helios].freeze

  # Mini-surveys persist into a slice of one singleton section in config.yaml.
  # On save the listed keys overwrite, missing ones are cleared, and any
  # sibling keys in the singleton (owned by other mini-surveys) survive
  # untouched. `#setting_data` returns the slice the mini-survey owns.
  SETTING_GROUPS = {
    'system_general' => { singleton: 'system', keys: %w[installation_date timezone currency] },
    'system_network' => { singleton: 'system', keys: %w[app_host] },
    'system_security' => { singleton: 'system', keys: %w[admin_password] },
    'dashboard_co2' => { singleton: 'dashboard', keys: %w[co2_emission_factor] },
    'dashboard_theme' => { singleton: 'dashboard', keys: %w[ui_theme] },
    'dashboard_network' => { singleton: 'dashboard', keys: %w[frame_ancestors host_port] },
    'ingest_settings' => { singleton: 'ingest', keys: %w[retention_hours] },
  }.freeze

  # The charger fields the prices survey collects on behalf of the
  # `senec_charger` section. `image` is not among them: the Software survey owns
  # it and it is never part of this survey's payload.
  SENEC_CHARGER_SURVEY_FIELDS = (ConfigSchema::SENEC_CHARGER_FIELDS - %w[image]).freeze

  # Survey fields persisted in a section other than the survey's own.
  # lockup_codeword and trusted_proxy_ranges are Dashboard environment
  # variables and keep living in the `dashboard` section, but surface in the
  # security and reverse-proxy surveys for UX grouping. `#setting_data` merges
  # them in for prefill; `#update` writes them back to their `dashboard` keys.
  BORROWED_FIELDS = {
    'system_security' => { 'lockup_codeword' => 'dashboard' },
    'reverse_proxy' => { 'trusted_proxy_ranges' => 'dashboard' },
    # The prices survey configures two services at once: the Tibber collector
    # (its own section) plus, where the preconditions hold, the SENEC charger
    # that consumes the prices. The charger's tuning is routed into its own
    # section, so both stay clean per-service collector configs — and the
    # charger section disappears once the survey blanks its fields.
    'tibber' => SENEC_CHARGER_SURVEY_FIELDS.index_with('senec_charger').freeze,
  }.freeze

  # Read-only pseudo-settings: they appear in the Advanced UI like real
  # settings (chip → modal with survey) but expose derived state instead of
  # persisting anything. `Configuration#setting_data` synthesises the payload
  # the survey prefills with, and `#update` refuses writes.
  READ_ONLY_SETTINGS = %w[storage].freeze

  # The Software survey shows a matrix of services (rows) × release
  # channels (columns). Each row stores its persisted image in a different
  # singleton, so we translate between the survey's channel tokens
  # (`'latest'`/`'develop'`) and the registry's full image URLs at load and
  # save time. See #software_setting_data / #update_software.
  SOFTWARE_SERVICES = {
    'dashboard' => { singleton: 'dashboard', registry: :DASHBOARD },
    'senec_collector' => { singleton: 'senec', registry: :SENEC_COLLECTOR },
    'shelly_collector' => { singleton: 'shelly', registry: :SHELLY_COLLECTOR },
    'mqtt_collector' => { singleton: 'mqtt', registry: :MQTT_COLLECTOR },
    'tibber_collector' => { singleton: 'tibber', registry: :TIBBER_COLLECTOR },
    'senec_charger' => { singleton: 'senec_charger', registry: :SENEC_CHARGER },
    'forecast_collector' => { singleton: 'forecast', registry: :FORECAST_COLLECTOR },
    'ingest' => { singleton: 'ingest', registry: :INGEST },
    'power_splitter' => { singleton: 'power_splitter', registry: :POWER_SPLITTER },
    'helios' => { singleton: 'helios', registry: :HELIOS },
  }.freeze

  # Per-service singletons whose `image` is owned by the Software survey.
  SOFTWARE_IMAGE_OWNERS = SOFTWARE_SERVICES.values.pluck(:singleton).uniq.freeze

  # `system` fields the Software survey owns besides the channel matrix: when
  # the stack checks for new images (see WatchtowerSchedule). They live in
  # `system` rather than the `watchtower` section because that section only
  # holds the service's own image, and are written with the same grouped
  # semantics as a mini-survey (see SETTING_GROUPS).
  SOFTWARE_SYSTEM_FIELDS = %w[update_mode update_interval update_time].freeze
  SOFTWARE_SYSTEM_GROUP = { singleton: 'system', keys: SOFTWARE_SYSTEM_FIELDS }.freeze

  # Settings shown on the Advanced page in full mode. `influxdb` exposes
  # only a couple of host-level toggles (e.g. UI port publication) here —
  # bucket/org/tokens are auto-managed and never user-editable in full mode.
  # `backup` is intentionally absent: its survey lives on the Backups page.
  SETTINGS = %w[
    deployment software
    system_general system_network system_security
    dashboard_co2 dashboard_theme dashboard_network
    influxdb reverse_proxy
    tibber
    storage
  ].freeze

  # On the Advanced page, settings render as compact chips clustered into
  # thematic groups. The keys are i18n slugs (advanced.show.groups.*); the
  # values list setting IDs in the order they should appear inside the group.
  # Mode filtering (`visible_settings`) and empty-group filtering happen in
  # `#advanced_groups` — this map is the static layout.
  ADVANCED_GROUPS = {
    'installation' => %w[deployment software system_general],
    'access' => %w[system_network influxdb dashboard_network reverse_proxy system_security],
    'data' => %w[ingest_settings storage],
    'energy_management' => %w[tibber],
    'dashboard' => %w[dashboard_co2 dashboard_theme],
  }.freeze

  # Settings shown in the configuration UI in collectors_only mode. The host
  # has no public surface (reverse_proxy/backup target the local dashboard/
  # postgres, which don't exist here) and `system_network` configures app_host,
  # which only matters when the dashboard runs locally.
  COLLECTORS_ONLY_SETTINGS = %w[
    deployment software
    system_general system_security
    influxdb
    tibber
  ].freeze

  # Settings shown in the configuration UI in dashboard_only mode. The
  # InfluxDB card is hidden because its only user-facing toggle (UI port
  # publication) is forced on anyway — remote collectors need to reach the
  # database across the LAN. `tibber` is listed for the same reason
  # #enforce_mode_constraints! keeps the section here: the collector only
  # fetches from a public API, so it runs alongside the dashboard and must
  # stay editable.
  DASHBOARD_ONLY_SETTINGS = %w[
    deployment software
    system_general system_network system_security
    dashboard_co2 dashboard_theme dashboard_network
    reverse_proxy
    tibber
    storage
  ].freeze

  # Source configurations shown when at least one sensor uses that source
  SOURCE_CONFIGS = %w[mqtt shelly forecast senec].freeze

  # All data sources (SOURCE_CONFIGS + external sources without own configuration)
  ALL_SOURCES = (SOURCE_CONFIGS + %w[external]).freeze

  # Sources allowed for sensors in dashboard_only mode. Device collectors
  # (senec/shelly/mqtt) talk to local hardware and run on a remote
  # collectors_only host that pushes into the dashboard's InfluxDB. The
  # forecast collector only fetches from public APIs and may run alongside
  # the dashboard, so it stays available together with `external`.
  DASHBOARD_ONLY_SOURCES = %w[external forecast].freeze

  # All valid setting names (real singletons + mini-survey IDs + software +
  # read-only pseudo-settings). Software has its own translation layer (see
  # SOFTWARE_SERVICES) instead of the generic SETTING_GROUPS mapping, but is
  # still a routable setting ID. READ_ONLY_SETTINGS are routable too — their
  # survey renders but writes are rejected.
  ALL = (SINGLETONS + SETTING_GROUPS.keys + READ_ONLY_SETTINGS + %w[software]).freeze

  # Key for unmanaged services and env vars (preserved from existing installations)
  UNMANAGED_KEY = '_unmanaged'.freeze

  # Top-level key tracking the schema version for migrations (see ConfigurationMigrator)
  SCHEMA_VERSION_KEY = '_schema_version'.freeze

  # Canonical order for config.yaml output
  YAML_ORDER = SINGLETONS.freeze

  YAML_HEADER = <<~HEADER.freeze
    # ============================================================
    # Managed by HELIOS — DO NOT EDIT MANUALLY!
    #
    # This file stores your HELIOS configuration.
    # It is rewritten whenever you apply changes in HELIOS.
    # Use the HELIOS web interface to modify your configuration.
    # ============================================================
  HEADER

  # Hash wrapper that allows method-style access: config.system.timezone
  class Data < Hash
    def self.wrap(hash)
      wrapped = new
      (hash || {}).each do |k, v|
        wrapped[k.to_s] = v.is_a?(Hash) ? wrap(v) : v
      end
      wrapped
    end

    def method_missing(name, ...)
      self[name.to_s]
    end

    def respond_to_missing?(name, include_private = false)
      key?(name.to_s) || super
    end
  end

  def self.path
    File.join(Rails.configuration.data_path, 'helios', YAML_FILENAME)
  end

  def self.delete!
    FileUtils.rm_f(path)
    Current.configuration = nil
  end

  # Serialize a config hash to the canonical YAML representation, including
  # the header comment. Used by save! and by fixture-generation tasks.
  def self.dump(data)
    YAML_HEADER + YAML.dump(data)
  end

  def self.current
    Current.configuration ||= new(path)
  end

  # In-memory Configuration from a raw data hash. Used by the import pipeline
  # to dry-run Export::Env against intermediate extractor data without
  # touching disk.
  def self.from_data(data)
    config = allocate
    config.send(:initialize_from_data, data)
    config
  end

  # Load and parse a config.yaml file from disk, returning the raw hash. Returns
  # an empty hash when the file is missing or empty. Centralizes the YAML
  # loader options (permitted classes) shared with ConfigurationMigrator.
  #
  # The parsed data is cached process-wide, keyed by file mtime — every request
  # builds a fresh Configuration instance (see `.current`) which used to re-parse
  # the YAML. Each call returns a deep_dup so per-instance mutations
  # (`#update`, `#save!`, ConfigurationMigrator) stay local; the atomic file
  # rename in `#save!` / `write_atomic!` bumps mtime and the next loader sees
  # the updated content.
  def self.load_file(path)
    return {} unless File.exist?(path)

    mtime = File.mtime(path).to_f
    Rails.cache.fetch([:configuration_data, path, mtime]) { parse_yaml_file(path) }.deep_dup
  end

  def self.parse_yaml_file(path)
    YAML.safe_load_file(path, permitted_classes: [Date]) || {}
  end
  private_class_method :parse_yaml_file

  def self.singleton?(setting)
    setting.to_s.in?(SINGLETONS)
  end

  def self.valid?(setting)
    setting.to_s.in?(ALL)
  end

  def self.source?(setting)
    setting.to_s.in?(ALL_SOURCES)
  end

  def initialize(path)
    @path = path
    @data = self.class.load_file(path)
  end

  # Used by Configuration.from_data to skip disk I/O. Reuses Configuration's
  # full surface area (singleton accessors, helper predicates) without going
  # through the file-backed initializer.
  def initialize_from_data(data)
    @path = nil
    @data = (data || {}).deep_stringify_keys
  end
  private :initialize_from_data

  # Dynamic singleton accessors: config.system, config.forecast, config.senec, etc.
  # Excluded singletons have hash-of-hashes shape and need their own sanitation
  # (see #sensors and #service_overrides).
  (SINGLETONS - %w[sensors service_overrides]).each do |setting|
    define_method(setting) do
      Data.wrap(@data[setting] || {})
    end
  end

  # --- Sensor access ---

  # All configured sensors as a hash: { 'inverter_power' => { 'source' => 'senec' }, ... }
  def sensors
    Data.wrap(@data['sensors'] || {})
  end

  # List of enabled sensor names
  def enabled_sensors
    @enabled_sensors ||= (@data['sensors'] || {}).keys.select { |name| SensorRegistry.valid?(name) }
  end

  # Get config for a specific sensor
  def sensor_config(name)
    Data.wrap((@data['sensors'] || {})[name.to_s] || {})
  end

  # All sensors using a specific source
  def sensors_with_source(source)
    (@data['sensors'] || {}).select { |_name, config| config['source'] == source.to_s }
  end

  # SENEC native fields to exclude from InfluxDB (SENEC_IGNORE), derived from
  # the sensor configuration. A field is ignored only on a genuine collision:
  # the sensor is fed by another source (Shelly, MQTT, external, ...) AND that
  # source writes into the *same* measurement:field the SENEC collector would
  # use. This is the "switched vendor, kept the measurement" case — e.g. a new
  # wallbox feeding SENEC:wallbox_charge_power so history and live data line up;
  # the SENEC collector must then stop writing that field. A foreign source
  # writing into a different measurement does not overlap, so nothing is
  # ignored. Disabled sensors are left untouched — only an active source counts.
  def senec_ignore_fields
    senec_measurement = senec.measurement.presence || SensorMappings::DEFAULT_MEASUREMENTS['senec']

    SensorMappings::SENEC_DEFAULTS.filter_map do |sensor_name, (_measurement, senec_field)|
      senec_field if foreign_sensor_collides?(sensor_name, senec_measurement, senec_field)
    end
  end

  # True when sensor_name is fed by a non-SENEC source that writes into the
  # exact measurement:field the SENEC collector would use itself.
  def foreign_sensor_collides?(sensor_name, senec_measurement, senec_field)
    config = sensor_config(sensor_name)
    source = config.source.to_s
    return false if source.blank? || source == 'senec'

    measurement = config.measurement.presence || SensorMappings.default_measurement(sensor_name, source)
    field = config.field.presence || SensorMappings.default_field(sensor_name, source)
    measurement == senec_measurement && field == senec_field
  end

  # Comma-separated form for the SENEC_IGNORE env var.
  def senec_ignore
    senec_ignore_fields.join(',')
  end

  # Sources currently in use by at least one sensor — plus `mqtt` whenever
  # standalone mappings exist and `shelly` whenever standalone devices exist,
  # so the broker / Shelly section stays editable in the UI even when no
  # HELIOS sensor consumes them. A Shelly device that does feed a sensor lives
  # on that `source: shelly` sensor (with its own device_id/host), so it never
  # needs shelly.devices to stay visible. In collectors_only mode the import
  # deliberately skips logical sensors (canonicalization happens on the
  # remote dashboard host), so we fall back to "section is configured" —
  # otherwise senec/shelly stay invisible despite running collectors.
  def active_sources
    used = collected_sources
    used &= DASHBOARD_ONLY_SOURCES if dashboard_only?
    ALL_SOURCES.select { |source| used.include?(source) }
  end

  # Enable/update a sensor. Returns true if data changed.
  #
  # `prune: false` defers shadowed-device cleanup to the caller — the batch
  # importer persists sensors in alphabetical order, so a shadowing sensor
  # (e.g. mqtt `heatpump_heating_power`) can land before the Shelly sensor
  # that keeps the device alive (`heatpump_power`); pruning per sensor would
  # then drop a device the later sensor still needs. The importer prunes once
  # after the full batch instead.
  def update_sensor(name, data, prune: true) # rubocop:disable Naming/PredicateMethod
    @data['sensors'] ||= {}
    raw = data.is_a?(Data) ? data.to_h : data
    sanitized = sanitize_sensor_data(raw)
    return false if @data['sensors'][name.to_s] == sanitized

    rename_mapping_name!(sensor_mqtt_name(name), sanitized['mqtt_name'])
    @data['sensors'][name.to_s] = sanitized
    save!
    prune_shadowed_shelly_devices! if prune
    true
  end

  # Picking SENEC as a source fills in every other sensor the collector can
  # deliver, so a fresh setup does not have to add them one by one.
  #
  # This is a convenience for that first pick, not a rule the configuration
  # keeps enforcing. Once SENEC is established, the sensor set belongs to the
  # user, and a sensor they removed must stay removed. inverter_power is the
  # case that matters: the total and the parts inverter_power_1..5 are
  # alternatives, never both, so a user who adds a second producer removes the
  # total on purpose. Restoring it would silently put house power back on the
  # total alone and drop that producer from the calculation.
  def auto_enable_senec_sensors!
    return [] unless senec_source_new?

    candidates = SensorRegistry::SENSORS.each_key.select do |name|
      SensorRegistry.sources_for(name).include?('senec') && !sensor_enabled?(name)
    end
    return [] if candidates.empty?

    @data['sensors'] ||= {}
    candidates.each { |name| @data['sensors'][name] = { 'source' => 'senec' } }
    save!
    candidates
  end

  # True while at most one sensor reads from SENEC. Callers run after saving
  # that sensor, so "one" is the pick that just happened and nothing before it.
  def senec_source_new?
    enabled_sensors.count { |name| sensor_config(name).source == 'senec' } <= 1
  end

  # Disable/remove a sensor
  def remove_sensor(name)
    @data['sensors']&.delete(name.to_s)
    save!
  end

  # Check if a sensor is enabled
  def sensor_enabled?(name)
    (@data['sensors'] || {}).key?(name.to_s)
  end

  # Standalone topics that mqtt-collector writes into InfluxDB without
  # feeding a HELIOS sensor. Stored under mqtt.mappings (mqtt-collector's
  # native key); addressed by zero-based index.
  def mqtt_topics
    Array(@data.dig('mqtt', 'mappings'))
  end

  def mqtt_topic(index)
    mqtt_topics[index.to_i]
  end

  def add_mqtt_topic(data)
    write_mqtt_topics(mqtt_topics + [sanitize_fields(fold_computed_formula(data, ''), MQTT_TOPIC_FIELDS)])
  end

  def update_mqtt_topic(index, data)
    list = mqtt_topics.dup
    previous = list[index.to_i]
    return unless previous

    sanitized = sanitize_fields(fold_computed_formula(data, ''), MQTT_TOPIC_FIELDS)
    rename_mapping_name!(previous['name'], sanitized['name'])
    list[index.to_i] = sanitized
    write_mqtt_topics(list)
  end

  def remove_mqtt_topic(index)
    list = mqtt_topics.dup
    return unless list.delete_at(index.to_i)

    write_mqtt_topics(list)
  end

  def shelly_devices
    Array(@data.dig('shelly', 'devices'))
  end

  # Every physical device the Shelly collector polls, in a uniform
  # device-shaped form (host/device_id/measurement/password/invert_power) —
  # regardless of whether it is represented on a `source: shelly` sensor
  # (device feeds a dashboard sensor) or as a standalone shelly.devices entry
  # (no consuming sensor). The export rolls both into a single CSV collector,
  # so a stack mixing the two stays intact. Sensors come first (config order),
  # then standalone devices.
  #
  # Deduplicated by physical identity: a 3-phase Shelly (3EM) feeds several
  # sensors (power_a/power_b/power_c) off one host+measurement, but the
  # collector must poll that device only once.
  def shelly_collector_devices
    from_sensors = sensors_with_source('shelly').map do |_name, config|
      {
        'host' => config['shelly_host'],
        'device_id' => config['shelly_device_id'],
        'measurement' => config['measurement'],
        'password' => config['shelly_password'],
        'invert_power' => config['shelly_invert_power'],
      }.compact
    end

    # Sensor-derived devices are sorted by measurement (case-insensitive) so the
    # exported CSV order is stable and matches the historical alphabetized order
    # of the former shelly.devices list. Standalone entries keep their stored
    # order, appended afterwards — pure-standalone stacks (collectors-only,
    # ghost devices) thus export byte-for-byte as before.
    from_sensors
      .uniq { |d| d.values_at('host', 'device_id', 'measurement') }
      .sort_by { |d| d['measurement'].to_s.downcase } + shelly_devices
  end

  def shelly_cloud?
    shelly&.connection == 'cloud'
  end

  def shelly_device(index)
    shelly_devices[index.to_i]
  end

  def add_shelly_device(data)
    write_shelly_devices(shelly_devices + [sanitize_fields(data, SHELLY_DEVICE_FIELDS)])
  end

  def update_shelly_device(index, data)
    list = shelly_devices.dup
    return unless list[index.to_i]

    list[index.to_i] = sanitize_fields(data, SHELLY_DEVICE_FIELDS)
    write_shelly_devices(list)
  end

  def remove_shelly_device(index)
    list = shelly_devices.dup
    return unless list.delete_at(index.to_i)

    write_shelly_devices(list)
  end

  # Measurements already produced by a HELIOS-managed collector other than
  # Shelly. A Shelly device targeting one of these would be a duplicate
  # writer — `source: external` is excluded on purpose, since the external
  # writer may well be the shelly-collector itself.
  def shadowing_measurements
    shadowing_sources = SOURCE_CONFIGS - %w[shelly]
    (@data['sensors'] || {}).each_value.filter_map do |config|
      config['measurement'] if shadowing_sources.include?(config['source'])
    end.to_set
  end

  # Measurements still consumed by a `source: shelly` sensor. A device feeding
  # one of these must survive even when another collector writes the same
  # measurement into a different field — SOLECTRUS lets several collectors
  # share a measurement (e.g. a Shelly power sensor and an MQTT heating-power
  # sensor both writing `heatpump`).
  def shelly_consumed_measurements
    (@data['sensors'] || {}).each_value.filter_map do |config|
      config['measurement'] if config['source'] == 'shelly'
    end.to_set
  end

  # Shelly devices whose measurement another collector already writes and that
  # no Shelly sensor still consumes — stale leftovers from moving the consuming
  # sensor to a different source.
  def shadowed_shelly_devices
    shadowing = shadowing_measurements
    consumed = shelly_consumed_measurements
    shelly_devices.select do |device|
      measurement = device['measurement']
      shadowing.include?(measurement) && consumed.exclude?(measurement)
    end
  end

  # Drops shelly.devices entries that another collector already writes, so a
  # shelly-collector left without any device can be orphaned in /services.
  # Returns true when something was removed.
  def prune_shadowed_shelly_devices! # rubocop:disable Naming/PredicateMethod
    shadowed = shadowed_shelly_devices
    return false if shadowed.empty?

    write_shelly_devices(shelly_devices - shadowed)
    true
  end

  # --- Source requirements ---

  def senec_required?
    sensors_with_source('senec').any?
  end

  def mqtt_required?
    sensors_with_source('mqtt').any?
  end

  def shelly_required?
    sensors_with_source('shelly').any?
  end

  def forecast_required?
    sensors_with_source('forecast').any?
  end

  # A forecast collector is actually running, so `INFLUX_MEASUREMENT_FORECAST`
  # is emitted and holds data. Mirrored by
  # `Export::Services::ForecastCollector.enabled?`. Sensor-driven, hence always
  # false in collectors_only mode.
  def forecast_available?
    forecast_required? && forecast.forecast.present?
  end

  # Tibber is not sensor-driven (it writes a standalone Prices measurement),
  # so there is no `sensors_with_source` gate. It runs whenever an API token
  # has been configured. The prices exist for the SENEC charger, but collecting
  # them without one is a valid (if exotic) choice: it builds the history a
  # future consumer could read.
  def tibber_enabled?
    tibber.token.present?
  end

  # The charger steers the battery over the local API, so it needs a battery
  # that HELIOS queries locally — V2.1/V3 with the local adapter. Cloud access
  # (Home 4, or a V3 in cloud mode) offers no such control, so charging is not
  # offered there at all, and a stack that pairs the two is refused outright
  # (see Import::CompatibilityCheck). `adapter == 'local'` implies V3/V2.1,
  # since Home 4 forces cloud access.
  #
  # Full mode only, asked of `mode` rather than of the sections: a
  # collectors_only host has no forecast to read (see #forecast_available?),
  # and a dashboard_only one has no battery — #enforce_mode_constraints! drops
  # the senec section there, but only for data that went through it. A config
  # read straight from disk or built via .from_data (the migration does) still
  # carries the old section, so the mode has to be checked here.
  def senec_charger_offered?
    senec.adapter == 'local' && mode == ConfigSchema::MODE_FULL
  end

  # The charger skips grid charging when enough PV yield is expected, so it also
  # reads the forecast. Until a forecast collector runs, the survey names the
  # missing dependency instead of offering the charging questions.
  def senec_charger_configurable?
    senec_charger_offered? && forecast_available?
  end

  # Charging is switched on. The Software survey can leave an `image` behind in
  # an otherwise blanked section, so the section's mere presence says nothing —
  # only its actual tuning does.
  def senec_charger_enabled?
    senec_charger.except('image').present?
  end

  # Export gate: everything the charger's compose service references must exist —
  # a local battery to steer (SENEC_HOST/SENEC_SCHEMA), the Tibber prices
  # (${INFLUX_MEASUREMENT_PRICES}) and the forecast
  # (${INFLUX_MEASUREMENT_FORECAST}).
  def senec_charger_available?
    senec_charger_configurable? && tibber_enabled?
  end

  # Field that must be set for the source's collector to start. Listed per
  # source to avoid treating a partially-filled section ({measurement: 'foo'})
  # as configured.
  SOURCE_REQUIRED_FIELDS = {
    'senec' => 'version',
    'mqtt' => 'mqtt_host',
    'shelly' => 'connection',
    'forecast' => 'forecast',
  }.freeze

  # What a standalone entry may store: every field of a mapping, so the
  # allowlist can never fall behind what the export emits.
  MQTT_TOPIC_FIELDS = ConfigSchema::MQTT_MAPPING_FIELDS

  SHELLY_DEVICE_FIELDS = %w[name measurement host device_id password invert_power].freeze

  def incomplete_sources
    @incomplete_sources ||= active_sources.select do |source|
      SOURCE_CONFIGS.include?(source) && !source_complete?(source)
    end
  end

  def incomplete?
    incomplete_sources.any?
  end

  # In collectors_only mode the collectors push to an external InfluxDB; without
  # a host they have nowhere to write. Local-mode fields (org/bucket/token) are
  # auto-generated and survive a mode switch, so a plain "section configured?"
  # check would mis-report a half-empty target as ready.
  def incomplete_influxdb?
    collectors_only? && influxdb.host.blank?
  end

  # system_general carries the user-supplied basics (currently the PV
  # commissioning date). The date is mandatory before the stack starts and is
  # never auto-filled, so a blank value marks the group incomplete. Skipped in
  # collectors_only mode, where the dashboard runs remotely (matches the survey).
  def incomplete_system_general?
    !collectors_only? && system.installation_date.blank?
  end

  # Setting ids that are still incomplete and therefore block stack start.
  # Single source of truth for both the per-setting warning badges and the
  # overall #configuration_complete? gate.
  def incomplete_settings
    ids = incomplete_sources.dup
    # incomplete_sources flags 'forecast' only when the `forecast` field itself
    # is blank; incomplete_forecast_location? applies only when it is present.
    # The two target disjoint states and never flag 'forecast' together.
    ids << 'forecast' if incomplete_forecast_location?
    ids << 'influxdb' if incomplete_influxdb?
    ids << 'system_general' if incomplete_system_general?
    ids
  end

  # pvnode API v2 is site-based: a configured site ID selects it, and location
  # and all PV strings live on the pvnode site rather than in HELIOS. Ships on
  # the stable channel since forecast-collector v0.10.0. The .env / compose
  # exporters read this as the single server-side switch (the survey re-derives
  # the same decision client-side from {forecast_pvnode_site_id}).
  def forecast_pvnode_v2?
    fc = forecast
    fc.forecast == 'pvnode' && fc.forecast_pvnode_site_id.present?
  end

  # The location-based pvnode API v1 cannot produce a forecast without the
  # site location and the first roof string (these are exactly the fields the
  # survey marks required for pvnode v1). A pvnode setup without a site ID uses
  # v1, so any missing field marks the section incomplete and the user fills it
  # in the forecast-collector survey.
  PVNODE_V1_REQUIRED_FIELDS = %w[
    forecast_latitude
    forecast_longitude
    forecast_declination1
    forecast_pvnode_azimuth1
    forecast_kwp1
  ].freeze

  def incomplete_forecast_location?
    return false unless forecast_required?

    fc = forecast
    return false unless fc.forecast == 'pvnode' && !forecast_pvnode_v2?

    PVNODE_V1_REQUIRED_FIELDS.any? { |field| fc.public_send(field).blank? }
  end

  def setting_incomplete?(setting)
    incomplete_settings.include?(setting)
  end

  # True when the configuration holds everything required to bring the stack
  # up: setup is done and no required section is still incomplete. Single
  # source of truth for every start affordance (status-bar button, compose-up
  # endpoints).
  def configuration_complete?
    setup_completed? && incomplete_settings.empty?
  end

  # Ingest recalculates house_power when a balcony power plant feeds into
  # the home grid and distorts the inverter-reported value. It runs alongside
  # the local InfluxDB only — in collectors_only mode there is nothing to
  # recalculate.
  #
  # SOLECTRUS routes ALL producers through Ingest so it can recompute
  # house_power from the complete picture (roof + balcony + grid + battery −
  # wallbox − heatpump …). HELIOS cannot route a source it does not manage, so
  # as soon as one Ingest input arrives via `source: external`, Ingest would
  # only ever see partial data. Rather than recalculate on an incomplete set,
  # HELIOS leaves a correct house_power to the external side and skips Ingest
  # entirely — an external source must deliver already-correct values.
  def ingest_required?
    !collectors_only? && balcony_sensors.any? && external_ingest_inputs.empty?
  end

  # Enabled Ingest inputs (INGEST_SENSORS) fed by an external source. Their
  # data reaches InfluxDB without passing through the Ingest write proxy, so
  # their presence disables Ingest (see #ingest_required?).
  def external_ingest_inputs
    @external_ingest_inputs ||= enabled_sensors.select do |name|
      SensorRegistry::INGEST_SENSORS.include?(name) &&
        sensor_config(name).source.to_s == 'external'
    end
  end

  # --- Deployment mode ---

  def mode
    @mode ||= deployment.mode.presence || ConfigSchema::MODE_FULL
  end

  def collectors_only?
    mode == ConfigSchema::MODE_COLLECTORS_ONLY
  end

  def dashboard_only?
    mode == ConfigSchema::MODE_DASHBOARD_ONLY
  end

  # --- Release channels ---

  # Does the named service (a SOFTWARE_SERVICES key) follow the development
  # channel? Surveys ask before they offer a setting that only a develop image
  # reads, so nobody on the stable channel is confronted with it.
  def develop_channel?(service)
    spec = SOFTWARE_SERVICES[service]
    return false unless spec

    image = (@data[spec[:singleton]] || {})['image']
    image.present? && image_channel(image) == 'develop'
  end

  # Reverse-proxy "external Traefik" mode: an external Traefik routes to the
  # stack's published host ports, so HELIOS runs no Traefik of its own (no
  # app_domain); an optional bind_ip pins where the ports are published.
  # The stored `mode` is authoritative; fall back to field presence for configs
  # saved before `mode` was persisted and for imported stacks. Mirrors the
  # tri-state in Configurations::SettingsController#reverse_proxy_mode.
  def reverse_proxy_external?
    return reverse_proxy.mode == 'external' if reverse_proxy.mode.present?

    reverse_proxy.app_domain.blank? && reverse_proxy.bind_ip.present?
  end

  # Reverse-proxy "managed Traefik" mode: HELIOS runs its own Traefik for the
  # configured app_domain and routes the dashboard/influxdb through it via
  # labels (no published host ports). The internal counterpart to
  # reverse_proxy_external?.
  def reverse_proxy_managed?
    !collectors_only? && reverse_proxy.app_domain.present?
  end

  # Settings visible in the configuration UI for the current mode. Ingest is
  # inserted right after influxdb whenever a balcony sensor activates it — the
  # two services sit next to each other in the data path and read more naturally
  # as neighbors on the card grid. Ingest only activates when all its inputs are
  # HELIOS-managed (see #ingest_required?), which today is full mode only, so the
  # influxdb anchor is always present; the append fallback is purely defensive.
  def visible_settings
    base = case mode
           when ConfigSchema::MODE_COLLECTORS_ONLY then COLLECTORS_ONLY_SETTINGS
           when ConfigSchema::MODE_DASHBOARD_ONLY then DASHBOARD_ONLY_SETTINGS
           else SETTINGS
           end
    return base unless ingest_required?

    insert_at = base.index('influxdb')
    insert_at ? base.dup.insert(insert_at + 1, 'ingest_settings') : base + %w[ingest_settings]
  end

  # Visible settings clustered into the thematic groups rendered on the
  # Advanced page. Returns an ordered hash of `{ group_key => [settings] }`,
  # skipping groups that have no visible setting in the current mode.
  def advanced_groups
    visible = visible_settings
    ADVANCED_GROUPS.each_with_object({}) do |(group, settings), result|
      present = settings & visible
      result[group] = present if present.any?
    end
  end

  def balcony_sensors
    @balcony_sensors ||= SensorRegistry::BALCONY_CAPABLE_SENSORS.select do |name|
      sensor_enabled?(name) && sensor_config(name).is_balcony
    end
  end

  # --- Sensor mappings for .env generation ---

  # Effective sensor mappings derived from sensor configuration
  def effective_sensor_mappings
    @effective_sensor_mappings ||= enabled_sensors.each_with_object({}) do |name, mappings|
      config = sensor_config(name)
      mapping = SensorMappings.mapping_for(name, config)
      mappings[name] = mapping if mapping
    end
  end

  # Sensor names excluded from house power calculation
  def excluded_from_house_power
    enabled_sensors.select do |name|
      sensor_config(name).exclude_from_house_power == true
    end.map(&:upcase)
  end

  # --- Generic singleton access ---

  # For real singletons, returns the section hash. For mini-survey IDs,
  # returns the slice the mini-survey owns (a `slice` of its parent section).
  # Borrowed fields (see BORROWED_FIELDS) and the `software` matrix are merged
  # in so form prefill and `configured?` see the survey's full view.
  def setting_data(setting)
    setting = setting.to_s
    return software_setting_data if setting == 'software'
    return read_only_setting_data(setting) if READ_ONLY_SETTINGS.include?(setting)

    Data.wrap(merge_borrowed_fields(own_section_data(setting), setting))
  end

  # Create or update a setting. Returns true if data changed.
  #
  # For real singletons (`'system'`, `'backup'`, …) the whole section is
  # replaced by the incoming hash — the survey's view of the section is the
  # full truth.
  #
  # For mini-survey IDs (`'system_security'`, …) only the keys the mini-survey
  # owns are touched: present keys overwrite, missing keys are deleted, and any
  # other keys in the singleton (owned by sibling mini-surveys) survive
  # untouched.
  #
  # Borrowed fields (see BORROWED_FIELDS) are split off first and written into
  # their own `dashboard` keys, never into the survey's own section.
  def update(setting, data)
    setting = setting.to_s
    return update_software(data) if setting == 'software'
    raise ArgumentError, "Setting '#{setting}' is read-only" if READ_ONLY_SETTINGS.include?(setting)

    raw = deep_unwrap(data)
    borrowed_changed = store_borrowed_fields!(setting, raw)

    group = SETTING_GROUPS[setting]
    return update_grouped(group, raw) || borrowed_changed if group

    if @data[setting] == raw
      borrowed_changed
    else
      @data[setting] = raw
      enforce_mode_constraints! if setting == 'deployment'
      save!
      true
    end
  end

  def configured?(setting)
    setting_data(setting).present?
  end

  # In collectors_only mode no logical sensors are imported (canonicalization
  # lives on the remote dashboard host) — accept any active source/raw mapping
  # as "set up" so the Services screen is reachable.
  def setup_completed?
    return true if enabled_sensors.any?

    collectors_only? && active_sources.any?
  end

  # Per-service compose-key overrides for managed services (ADR-0015).
  # Returns { service_name => { 'labels' => [...], 'ports' => [...], ... } }.
  def service_overrides
    Data.wrap(@data['service_overrides'] || {})
  end

  # Access unmanaged services and env vars
  def unmanaged
    Data.wrap(@data[UNMANAGED_KEY] || {})
  end

  # Store unmanaged services and env vars. Drop the key entirely when empty so
  # removing the last unmanaged service leaves no dangling `_unmanaged:` line.
  def update_unmanaged(data)
    if data.presence
      @data[UNMANAGED_KEY] = data
    else
      @data.delete(UNMANAGED_KEY)
    end
    save!
  end

  # True when `name` is a service preserved verbatim from an existing
  # installation (under `_unmanaged.services`) — HELIOS exports it but does
  # not manage its definition, so it can only be removed, never re-added.
  def unmanaged_service?(name)
    services = unmanaged.services
    services.is_a?(Hash) && services.key?(name.to_s)
  end

  # Permanently drop an unmanaged service from the configuration. Its
  # env_values live inside the service entry and are removed with it; the
  # top-level `_unmanaged.env_vars` (orphan .env lines) are left untouched.
  # Returns false when no such unmanaged service exists.
  def remove_unmanaged_service(name) # rubocop:disable Naming/PredicateMethod
    # Operate on the raw (plain-Hash) data, not the Data-wrapped reader, so the
    # value written back stays free of Configuration::Data objects in the YAML.
    data = @data[UNMANAGED_KEY]
    services = data && data['services']
    return false unless services.is_a?(Hash) && services.key?(name.to_s)

    services.delete(name.to_s)
    data.delete('services') if services.blank?
    update_unmanaged(data)
    true
  end

  def save!
    write_yaml_file! if @path

    @enabled_sensors = nil
    @balcony_sensors = nil
    @external_ingest_inputs = nil
    @effective_sensor_mappings = nil
    @incomplete_sources = nil
    @mode = nil
    Current.configuration = nil
  end

  def ordered_data
    result = {}
    stamp_schema_version!(result)
    YAML_ORDER.each { |key| result[key] = @data[key] if @data.key?(key) }
    sanitize_all_sensors!(result) if result.key?('sensors')
    sanitize_service_overrides!(result) if result.key?('service_overrides')
    sanitize_sections!(result)
    prune_orphan_ingest!(result)
    result[UNMANAGED_KEY] = @data[UNMANAGED_KEY] if @data.key?(UNMANAGED_KEY)
    result
  end

  # Drop the `ingest:` section when no sensor is flagged as balcony — Ingest is
  # only meaningful for balcony-power recalculation, so an orphan section is
  # configuration noise (and would re-activate the service on export).
  #
  # Skipped while sensor data still holds raw "MEASUREMENT:field" strings
  # (mid-import, before SensorPersister normalizes them to hash form); the next
  # save after persistence reaches the canonical shape and prunes correctly.
  def prune_orphan_ingest!(result)
    return unless result.key?('ingest')

    sensors = result['sensors'] || {}
    return if sensors.each_value.any? { |v| !v.is_a?(Hash) }

    balcony_present = SensorRegistry::BALCONY_CAPABLE_SENSORS.any? do |name|
      sensors.dig(name, 'is_balcony') == true
    end
    return if balcony_present

    result.delete('ingest')
  end

  # Preserve a higher version that may already be stored (e.g. file written
  # by a newer HELIOS) instead of silently downgrading the stamp. Skipped
  # while no migrations are registered, so legacy files stay untouched until
  # the first migration ships.
  def stamp_schema_version!(result)
    existing = @data[SCHEMA_VERSION_KEY].to_i
    target = [existing, ConfigurationMigrations.current_version].max
    result[SCHEMA_VERSION_KEY] = target if target.positive?
  end

  SENSOR_FIELDS_BY_SOURCE = {
    'senec' => %w[source measurement field is_balcony],
    'forecast' => %w[source measurement field],
    'external' => %w[source measurement field name exclude_from_house_power is_balcony],
    'shelly' => %w[
      source measurement field name shelly_connection shelly_host shelly_interval shelly_password
      shelly_device_id shelly_invert_power exclude_from_house_power is_balcony
    ],
    # The mapping fields come from the schema, so a new collector option cannot
    # be stripped here while the export still emits it.
    'mqtt' => [
      'source',
      'name',
      *ConfigSchema::MQTT_MAPPING_SENSOR_KEYS.values,
      'exclude_from_house_power',
      'is_balcony',
    ],
  }.freeze

  private

  # Synthesises the payload a read-only pseudo-setting's survey prefills
  # with. Routed via `setting_data` so the SettingForm component picks it up
  # without any special-casing on its side.
  def read_only_setting_data(setting)
    case setting
    when 'storage' then Data.wrap(StoragePaths.call(configuration: self))
    end
  end

  # The raw section/slice a survey owns, before borrowed fields are merged in.
  def own_section_data(setting)
    group = SETTING_GROUPS[setting]
    return (@data[group[:singleton]] || {}).slice(*group[:keys]) if group

    (@data[setting] || {}).dup
  end

  # Merges a survey's borrowed fields (see BORROWED_FIELDS) into `base`.
  def merge_borrowed_fields(base, setting)
    BORROWED_FIELDS.fetch(setting, {}).each do |field, section|
      value = (@data[section] || {})[field]
      base[field] = value if value.present?
    end
    base
  end

  # Extracts a survey's borrowed fields from `raw` (mutating it) and writes
  # each into its foreign section. Returns true if any borrowed value changed.
  def store_borrowed_fields!(setting, raw)
    changed = false
    BORROWED_FIELDS.fetch(setting, {}).each do |field, section|
      next unless raw.key?(field)

      changed = true if store_section_field(section, field, raw.delete(field))
    end
    save! if changed
    changed
  end

  # Writes a single field into a singleton section without disturbing its
  # other keys. A blank value removes the key (and the section, if it empties).
  def store_section_field(section, field, value) # rubocop:disable Naming/PredicateMethod
    current = @data[section]&.dup || {}
    return false unless section_field_changes?(current, field, value)

    if value.blank?
      current.delete(field)
    else
      current[field] = value
    end

    if current.empty?
      @data.delete(section)
    else
      @data[section] = current
    end
    true
  end

  def section_field_changes?(current, field, value)
    return current.key?(field) if value.blank?

    current[field] != value
  end

  def update_grouped(group, data) # rubocop:disable Naming/PredicateMethod
    singleton = group[:singleton]
    keys = group[:keys]
    incoming = deep_unwrap(data).slice(*keys)

    current = @data[singleton]&.dup || {}
    next_section = current.merge(incoming)
    (keys - incoming.keys).each { |k| next_section.delete(k) }

    return false if current == next_section

    if next_section.empty?
      @data.delete(singleton)
    else
      @data[singleton] = next_section
    end
    save!
    true
  end

  # Read side of the Software survey: the persisted image URL in each
  # service-owning singleton is mapped back to a `'latest'`/`'develop'` token
  # so the matrix can preselect the right column. Unrecognised URLs (legacy
  # tags, registry overrides) leave the row blank.
  def software_setting_data
    channels = software_channel_tokens
    payload = (@data['system'] || {}).slice(*SOFTWARE_SYSTEM_FIELDS).compact_blank
    payload['service_channels'] = channels if channels.any?
    Data.wrap(payload)
  end

  def software_channel_tokens
    SOFTWARE_SERVICES.each_with_object({}) do |(key, spec), result|
      image = (@data[spec[:singleton]] || {})['image']
      token = software_channel_for(spec[:registry], image)
      result[key] = token if token
    end
  end

  # Write side: translate `'latest'`/`'develop'` tokens into the registry's
  # full image URL and merge into each service's singleton. The update-check
  # fields ride along into `system`.
  def update_software(data)
    raw = deep_unwrap(data)
    changed = apply_software_channels(raw['service_channels'] || {})
    # Grouped semantics for the update-check fields: what the survey submits is
    # the truth, anything it left out is removed. SurveyJS drops the field of
    # the mode that isn't active, so config.yaml never keeps a setting that
    # nothing acts on.
    changed = true if update_grouped(SOFTWARE_SYSTEM_GROUP, raw)
    save! if changed
    changed
  end

  def apply_software_channels(channels)
    changed = false
    SOFTWARE_SERVICES.each do |key, spec|
      token = channels[key]
      next if token.blank?

      image = software_image_for(spec[:registry], token)
      next unless image
      next unless merge_singleton_field(spec[:singleton], 'image', image)

      changed = true
    end
    changed
  end

  def software_channel_for(registry, image)
    return nil if image.blank?

    choices = DockerImages.choices(registry)
    return nil unless choices&.include?(image)

    image_channel(image)
  end

  def software_image_for(registry, token)
    choices = DockerImages.choices(registry)
    return nil unless choices

    choices.find { |image| image_channel(image) == token }
  end

  # The channel token (`'latest'`/`'develop'`) is the tag part of an image URL.
  def image_channel(image)
    image.split(':').last
  end

  def merge_singleton_field(singleton, key, value) # rubocop:disable Naming/PredicateMethod
    current = @data[singleton]&.dup || {}
    return false if current[key] == value

    current[key] = value
    @data[singleton] = current
    true
  end

  def write_yaml_file!
    dir = File.dirname(@path)
    FileUtils.mkdir_p(dir) unless File.directory?(dir)

    tmp_path = "#{@path}.tmp"
    File.write(tmp_path, self.class.dump(ordered_data))
    File.rename(tmp_path, @path)
  end

  def sanitize_fields(data, fields)
    deep_unwrap(data).slice(*fields).compact_blank
  end

  # The surveys ask for the two kinds of formula in two questions, because a
  # formula over a topic reads {value} while a calculated one reads the names
  # of other mappings, and one question could not validate both. mqtt-collector
  # knows a single MAPPING_X_FORMULA, so they are folded here. The UI-only key
  # is dropped by the field slice right after.
  # Only the incoming survey payload carries the UI-only key, so the stored
  # sensors this runs over on every save are returned untouched. Unwrapping
  # them first would rebuild every sensor hash for nothing.
  def fold_computed_formula(data, prefix)
    computed = data["#{prefix}computed_formula"]
    return data if computed.blank?

    deep_unwrap(data).merge("#{prefix}formula" => computed)
  end

  # A sensor can still be stored as a bare "measurement:field" string, so the
  # entry is not always a hash.
  def sensor_mqtt_name(name)
    entry = @data['sensors'][name.to_s]
    entry['mqtt_name'] if entry.is_a?(Hash)
  end

  # Carries a renamed MAPPING_X_NAME into every formula that reads it, in both
  # kinds of entry. Without this the collector would refuse to start on the
  # next export, naming a reference that no mapping defines any more, and that
  # message is only visible in its own log.
  #
  # Clearing a name is not handled here: the surveys make the field mandatory
  # while something reads it, so the case does not arise through the UI.
  def rename_mapping_name!(previous, current)
    return if previous.blank? || current.blank? || previous == current

    from = "{#{previous}}"
    to = "{#{current}}"

    rewrite_formula_key!((@data['sensors'] || {}).values, 'mqtt_formula', from, to)
    rewrite_formula_key!(mqtt_topics, 'formula', from, to)
  end

  def rewrite_formula_key!(entries, key, from, to)
    entries.each do |entry|
      next unless entry.is_a?(Hash) && entry[key]&.include?(from)

      entry[key] = entry[key].gsub(from, to)
    end
  end

  def write_mqtt_topics(list)
    @data['mqtt'] ||= {}
    if list.empty?
      @data['mqtt'].delete('mappings')
    else
      @data['mqtt']['mappings'] = list
    end
    save!
  end

  def write_shelly_devices(list)
    @data['shelly'] ||= {}
    if list.empty?
      @data['shelly'].delete('devices')
    else
      @data['shelly']['devices'] = list
    end
    save!
  end

  # Recursively converts Configuration::Data (and any nested Data) back into
  # plain Hash/Array structures so YAML.safe_load can read them back.
  def deep_unwrap(value)
    case value
    when Hash then value.each_with_object({}) { |(k, v), h| h[k.to_s] = deep_unwrap(v) }
    when Array then value.map { |v| deep_unwrap(v) }
    else value
    end
  end

  def source_complete?(source)
    setting_data(source)[SOURCE_REQUIRED_FIELDS.fetch(source)].present?
  end

  def collected_sources
    used = (@data['sensors'] || {}).each_value.filter_map { |config| config['source'] }.to_set
    used << 'mqtt' if mqtt_topics.any?
    used << 'shelly' if shelly_devices.any?
    SOURCE_CONFIGS.each { |source| used << source if configured?(source) } if collectors_only?
    used
  end

  # Drop config sections that are unreachable in the current mode and rewrite
  # sensors when the mode restricts their sources. Idempotent — re-running on
  # an already clean config is a no-op.
  #
  # Postgres/Redis/Influx data sections (and their auto-generated passwords)
  # stay untouched on purpose: dropping them would orphan the on-disk volumes
  # the next time the mode flips back.
  def enforce_mode_constraints!
    case @data.dig('deployment', 'mode')
    when ConfigSchema::MODE_DASHBOARD_ONLY
      # senec_charger goes with senec: it steers the battery over the local
      # API, so it belongs wherever that hardware is reachable. `tibber` stays,
      # like `forecast` — both only fetch from a public API and keep running
      # alongside the dashboard.
      %w[shelly senec senec_charger mqtt].each { |key| @data.delete(key) }
      rewrite_sensors_to_external!
      strip_influxdb_fields!(ConfigSchema::INFLUXDB_EXTERNAL_FIELDS)
    when ConfigSchema::MODE_COLLECTORS_ONLY
      %w[reverse_proxy backup sensors].each { |key| @data.delete(key) }
      strip_influxdb_fields!(ConfigSchema::INFLUXDB_OPTIONAL_FIELDS)
    else
      # MODE_FULL (or missing — defaults to full)
      strip_influxdb_fields!(ConfigSchema::INFLUXDB_EXTERNAL_FIELDS)
    end
  end

  # External InfluxDB connection fields (host/port/schema) belong only in
  # collectors_only mode; local-container fields (publish_port/host_port/
  # use_hashed_tokens) belong only in modes with a local InfluxDB. Switching
  # between modes through the UI used to leave the now-irrelevant fields
  # behind, so the running stack pointed at the wrong target on the next
  # render. Removing them here keeps config.yaml in sync with the mode.
  def strip_influxdb_fields!(fields)
    section = @data['influxdb']
    return unless section.is_a?(Hash)

    fields.each { |field| section.delete(field) }
  end

  def rewrite_sensors_to_external!
    sensors = @data['sensors']
    return unless sensors.is_a?(Hash)

    allowed = SENSOR_FIELDS_BY_SOURCE.fetch('external')
    sensors.transform_values! do |config|
      next config unless config.is_a?(Hash)
      next config if %w[external forecast].include?(config['source'])

      config.merge('source' => 'external').slice(*allowed)
    end
  end

  def sanitize_sections!(result)
    result.each do |section, data|
      next unless data.is_a?(Hash)

      fields = ConfigSchema.fields_for(section)
      next unless fields.is_a?(Array)

      result[section] = data.slice(*fields)
    end
  end

  def sanitize_sensor_data(data)
    return data unless data.is_a?(Hash)

    source = data['source']
    allowed = SENSOR_FIELDS_BY_SOURCE[source]
    return data unless allowed

    fold_computed_formula(data, 'mqtt_').slice(*allowed).compact_blank
  end

  def sanitize_all_sensors!(result)
    raw = result['sensors']
    canonical_order = SensorRegistry::GROUPS.values.flatten
    ordered = canonical_order.each_with_object({}) do |name, hash|
      hash[name] = sanitize_sensor_data(raw[name]) if raw.key?(name)
    end
    # Append any sensors not in GROUPS (shouldn't happen, but safe)
    raw.each { |name, v| ordered[name] ||= sanitize_sensor_data(v) }
    result['sensors'] = ordered
  end

  # Drop unknown override keys per service and remove empty service entries.
  # The allowlist is the single gate — anything outside is silently discarded
  # at save time, mirroring the import-time behavior (ADR-0015).
  def sanitize_service_overrides!(result)
    raw = result['service_overrides']
    return result['service_overrides'] = nil unless raw.is_a?(Hash)

    sanitized = raw.each_with_object({}) do |(service, overrides), hash|
      next unless overrides.is_a?(Hash)

      filtered = overrides.slice(*ConfigSchema::SERVICE_OVERRIDES_ALLOWED_KEYS).compact_blank
      hash[service.to_s] = filtered if filtered.any?
    end

    if sanitized.any?
      result['service_overrides'] = sanitized
    else
      result.delete('service_overrides')
    end
  end
end
