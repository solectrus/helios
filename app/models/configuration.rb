class Configuration
  YAML_FILENAME = 'config.yaml'.freeze

  # Singletons exist at most once per configuration
  SINGLETONS = %w[
    system dashboard postgresql influxdb redis
    watchtower forecast senec mqtt shelly reverse_proxy backup sensors ingest
  ].freeze

  # Sections hidden from the configuration UI (auto-managed)
  HIDDEN = %w[dashboard postgresql influxdb redis watchtower ingest].freeze

  # Settings shown in the configuration UI (non-hidden singletons, excluding sensors and source configs)
  SETTINGS = %w[system reverse_proxy backup].freeze

  # Source configurations shown when at least one sensor uses that source
  SOURCE_CONFIGS = %w[senec mqtt shelly forecast].freeze

  # All data sources (SOURCE_CONFIGS + external sources without own configuration)
  ALL_SOURCES = (SOURCE_CONFIGS + %w[external]).freeze

  # All valid setting names
  ALL = SINGLETONS.freeze

  # Key for unmanaged services and env vars (preserved from existing installations)
  UNMANAGED_KEY = '_unmanaged'.freeze

  # Canonical order for config.yaml output
  YAML_ORDER = SINGLETONS.freeze

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

  def self.current
    Current.configuration ||= new(path)
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
    @data = File.exist?(path) ? YAML.safe_load_file(path, permitted_classes: [Date]) || {} : {}
  end

  # Dynamic singleton accessors: config.system, config.forecast, config.senec, etc.
  (SINGLETONS - ['sensors']).each do |setting|
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

  # Sources currently in use by at least one sensor
  def active_sources
    used = (@data['sensors'] || {}).each_value.filter_map { |config| config['source'] }.to_set
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

  # Disable/remove a sensor
  def remove_sensor(name)
    @data['sensors']&.delete(name.to_s)
    save!
  end

  # Check if a sensor is enabled
  def sensor_enabled?(name)
    (@data['sensors'] || {}).key?(name.to_s)
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

  # Ingest recalculates house_power when a balcony power plant feeds into
  # the home grid and distorts the inverter-reported value.
  def ingest_required?
    balcony_sensors.any?
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

  # Device names for each sensor (display name or sensor name)
  def sensor_device_names
    enabled_sensors.each_with_object({}) do |name, names|
      config = sensor_config(name)
      names[name] = config.name.presence || name
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
    raw = data.is_a?(Data) ? data.to_h : data
    return false if @data[setting.to_s] == raw

    @data[setting.to_s] = raw
    save!
    true
  end

  def configured?(setting)
    setting_data(setting).present?
  end

  def setup_completed?
    enabled_sensors.any?
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
    File.write(tmp_path, YAML.dump(ordered_data))
    File.rename(tmp_path, @path)

    @enabled_sensors = nil
    @balcony_sensors = nil
    @effective_sensor_mappings = nil
    Current.configuration = nil
  end

  def ordered_data
    result = YAML_ORDER.each_with_object({}) do |key, hash|
      hash[key] = @data[key] if @data.key?(key)
    end
    sanitize_all_sensors!(result) if result.key?('sensors')
    sanitize_sections!(result)
    result[UNMANAGED_KEY] = @data[UNMANAGED_KEY] if @data.key?(UNMANAGED_KEY)
    result
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
end
