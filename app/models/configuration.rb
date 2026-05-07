class Configuration # rubocop:disable Metrics/ClassLength
  YAML_FILENAME = 'config.yaml'.freeze

  # Singletons exist at most once per configuration
  SINGLETONS = %w[
    deployment system dashboard postgresql influxdb redis
    watchtower forecast senec mqtt shelly reverse_proxy backup sensors ingest power_splitter
    service_overrides
  ].freeze

  # Sections hidden from the configuration UI (auto-managed)
  HIDDEN = %w[postgresql influxdb redis watchtower ingest power_splitter].freeze

  # Settings shown in the configuration UI in full mode
  SETTINGS = %w[deployment system dashboard reverse_proxy backup].freeze

  # Settings shown in the configuration UI in collectors_only mode
  # (reverse_proxy/backup target the local dashboard/postgres, which don't exist here)
  COLLECTORS_ONLY_SETTINGS = %w[deployment system influxdb].freeze

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

  # All valid setting names
  ALL = SINGLETONS.freeze

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

  # Load and parse a config.yaml file from disk, returning the raw hash. Returns
  # an empty hash when the file is missing or empty. Centralizes the YAML
  # loader options (permitted classes) shared with ConfigurationMigrator.
  def self.load_file(path)
    return {} unless File.exist?(path)

    YAML.safe_load_file(path, permitted_classes: [Date]) || {}
  end

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

  # Sources currently in use by at least one sensor — plus `mqtt` whenever
  # standalone mappings exist, so the broker stays editable in the UI even
  # when no HELIOS sensor consumes them. In collectors_only mode the import
  # deliberately skips logical sensors (canonicalization happens on the
  # remote dashboard host), so we fall back to "section is configured" —
  # otherwise senec/shelly stay invisible despite running collectors.
  def active_sources
    used = collected_sources
    used &= DASHBOARD_ONLY_SOURCES if dashboard_only?
    ALL_SOURCES.select { |source| used.include?(source) }
  end

  # Enable/update a sensor. Returns true if data changed.
  def update_sensor(name, data) # rubocop:disable Naming/PredicateMethod
    @data['sensors'] ||= {}
    raw = data.is_a?(Data) ? data.to_h : data
    sanitized = sanitize_sensor_data(raw)
    return false if @data['sensors'][name.to_s] == sanitized

    @data['sensors'][name.to_s] = sanitized
    save!
    true
  end

  def auto_enable_senec_sensors!
    candidates = SensorRegistry::SENSORS.each_key.select do |name|
      SensorRegistry.sources_for(name).include?('senec') && !sensor_enabled?(name)
    end
    return [] if candidates.empty?

    @data['sensors'] ||= {}
    candidates.each { |name| @data['sensors'][name] = { 'source' => 'senec' } }
    save!
    candidates
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
    write_mqtt_topics(mqtt_topics + [sanitize_fields(data, MQTT_TOPIC_FIELDS)])
  end

  def update_mqtt_topic(index, data)
    list = mqtt_topics.dup
    return unless list[index.to_i]

    list[index.to_i] = sanitize_fields(data, MQTT_TOPIC_FIELDS)
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

  # Field that must be set for the source's collector to start. Listed per
  # source to avoid treating a partially-filled section ({measurement: 'foo'})
  # as configured.
  SOURCE_REQUIRED_FIELDS = {
    'senec' => 'version',
    'mqtt' => 'mqtt_host',
    'shelly' => 'connection',
    'forecast' => 'forecast',
  }.freeze

  MQTT_TOPIC_FIELDS = %w[
    topic measurement field type
    json_key json_path json_formula formula
    min max null_to_zero
  ].freeze

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

  # Ingest recalculates house_power when a balcony power plant feeds into
  # the home grid and distorts the inverter-reported value. It runs alongside
  # the local InfluxDB only — in collectors_only mode there is nothing to
  # recalculate. A balcony sensor activates ingest automatically; an
  # explicitly configured `ingest:` section keeps it deployed even without
  # a balcony sensor (testing or pre-balcony staging).
  def ingest_required?
    !collectors_only? && (balcony_sensors.any? || ingest.present?)
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

  # Settings visible in the configuration UI for the current mode.
  def visible_settings
    collectors_only? ? COLLECTORS_ONLY_SETTINGS : SETTINGS
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

  def setting_data(setting)
    Data.wrap(@data[setting.to_s] || {})
  end

  # Create or update a singleton setting. Returns true if data changed.
  def update(setting, data) # rubocop:disable Naming/PredicateMethod
    raw = deep_unwrap(data)
    return false if @data[setting.to_s] == raw

    @data[setting.to_s] = raw
    enforce_mode_constraints! if setting.to_s == 'deployment'
    save!
    true
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

  # Store unmanaged services and env vars
  def update_unmanaged(data)
    @data[UNMANAGED_KEY] = data.presence
    save!
  end

  def save!
    dir = File.dirname(@path)
    FileUtils.mkdir_p(dir) unless File.directory?(dir)

    tmp_path = "#{@path}.tmp"
    File.write(tmp_path, self.class.dump(ordered_data))
    File.rename(tmp_path, @path)

    @enabled_sensors = nil
    @balcony_sensors = nil
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
    result[UNMANAGED_KEY] = @data[UNMANAGED_KEY] if @data.key?(UNMANAGED_KEY)
    result
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
    'mqtt' => %w[
      source name measurement field
      mqtt_topic mqtt_payload_type
      mqtt_json_key mqtt_json_path mqtt_json_formula mqtt_formula
      mqtt_min mqtt_max mqtt_null_to_zero
      exclude_from_house_power is_balcony
    ],
  }.freeze

  private

  def sanitize_fields(data, fields)
    deep_unwrap(data).slice(*fields).compact_blank
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
      %w[shelly senec mqtt].each { |key| @data.delete(key) }
      rewrite_sensors_to_external!
    when ConfigSchema::MODE_COLLECTORS_ONLY
      %w[reverse_proxy backup sensors].each { |key| @data.delete(key) }
    end
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

    data.slice(*allowed).compact_blank
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
