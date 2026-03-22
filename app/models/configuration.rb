class Configuration
  YAML_FILENAME = 'config.yaml'.freeze

  # Singletons exist at most once per configuration
  SINGLETONS = %w[
    system postgresql influxdb redis
    watchtower forecast senec mqtt shelly reverse_proxy backup sensors
  ].freeze

  # Sections hidden from the configuration UI (auto-managed)
  HIDDEN = %w[postgresql influxdb redis watchtower].freeze

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

  def self.current
    path = File.join(Rails.configuration.helios_stack_path, YAML_FILENAME)
    new(path)
  end

  def self.singleton?(setting)
    setting.to_s.in?(SINGLETONS)
  end

  def self.valid?(setting)
    setting.to_s.in?(ALL)
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
    (@data['sensors'] || {}).keys.select { |name| SensorRegistry.valid?(name) }
  end

  # Get config for a specific sensor
  def sensor_config(name)
    Data.wrap((@data['sensors'] || {})[name.to_s] || {})
  end

  # All sensors using a specific source
  def sensors_with_source(source)
    (@data['sensors'] || {}).select { |_name, config| config['source'] == source.to_s }
  end

  # Enable/update a sensor
  def update_sensor(name, data)
    @data['sensors'] ||= {}
    raw = data.is_a?(Data) ? data.to_h : data
    @data['sensors'][name.to_s] = sanitize_sensor_data(raw)
    save!
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

  # --- Sensor mappings for .env generation ---

  # Effective sensor mappings derived from sensor configuration
  def effective_sensor_mappings
    enabled_sensors.each_with_object({}) do |name, mappings|
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

  # Check if Ingest service is needed (multiple inverter power sensors)
  def ingest_required?
    inverter_sensors = enabled_sensors.select { |n| n.start_with?('inverter_power_') && n.match?(/\d$/) }
    inverter_sensors.size > 1
  end

  # --- Generic singleton access ---

  def setting_data(setting)
    Data.wrap(@data[setting.to_s] || {})
  end

  # Create or update a singleton setting
  def update(setting, data)
    raw = data.is_a?(Data) ? data.to_h : data
    @data[setting.to_s] = raw
    save!
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
  end

  def ordered_data
    result = YAML_ORDER.each_with_object({}) do |key, hash|
      hash[key] = @data[key] if @data.key?(key)
    end
    sanitize_all_sensors!(result) if result.key?('sensors')
    result[UNMANAGED_KEY] = @data[UNMANAGED_KEY] if @data.key?(UNMANAGED_KEY)
    result
  end

  SENSOR_FIELDS_BY_SOURCE = {
    'senec' => %w[source measurement field],
    'forecast' => %w[source measurement field],
    'external' => %w[source measurement field name exclude_from_house_power],
    'shelly' => %w[
      source measurement field name shelly_connection shelly_host shelly_interval shelly_password
      shelly_cloud_server shelly_auth_key shelly_device_id shelly_invert_power
      exclude_from_house_power
    ],
    'mqtt' => %w[
      source measurement field name mqtt_topic mqtt_payload_type mqtt_json_key mqtt_formula
      exclude_from_house_power
    ],
  }.freeze

  private

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
