class Configuration
  YAML_FILENAME = 'config.yaml'.freeze

  # Devices can exist multiple times (e.g. two inverters)
  DEVICES = %w[inverter battery wallbox car heatpump consumer].freeze

  # Singletons exist at most once per configuration
  SINGLETONS = %w[
    system dashboard postgresql influxdb redis
    watchtower forecast reverse_proxy backup sensors
  ].freeze

  # Sections hidden from the configuration UI (auto-managed)
  HIDDEN = %w[postgresql influxdb redis watchtower sensors].freeze

  # All valid setting names
  ALL = (DEVICES + SINGLETONS).freeze

  # Canonical order for config.yaml output
  YAML_ORDER = (SINGLETONS + DEVICES).freeze

  # Mapping setting name → YAML key (identity mapping, kept for indirection)
  YAML_KEYS = ALL.index_with(&:itself).freeze

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

    def respond_to_missing?(...)
      true
    end
  end

  Device = Struct.new(:type, :name, :data)

  def self.current
    path = File.join(Rails.configuration.helios_stack_path, YAML_FILENAME)
    new(path)
  end

  def self.device?(setting)
    setting.to_s.in?(DEVICES)
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

  # Dynamic singleton accessors: config.system, config.forecast, etc.
  SINGLETONS.each do |setting|
    define_method(setting) do
      Data.wrap(@data[YAML_KEYS[setting]] || {})
    end
  end

  # Dynamic device accessors: config.inverter('SMA'), config.battery('Speicher'), etc.
  DEVICES.each do |setting|
    define_method(setting) do |device_name|
      Data.wrap(@data.dig(YAML_KEYS[setting], device_name.to_s) || {})
    end
  end

  # Generic lookup for dynamic dispatch (when the setting name is a variable)
  def setting_data(setting, device_name = nil)
    yaml_key = YAML_KEYS[setting.to_s]
    return Data.wrap({}) unless yaml_key

    raw = if self.class.device?(setting)
            device_name ? (@data.dig(yaml_key, device_name.to_s) || {}) : {}
          else
            @data[yaml_key] || {}
          end
    Data.wrap(raw)
  end

  # All devices of a given type
  def devices_of(setting)
    yaml_key = YAML_KEYS[setting.to_s]
    (@data[yaml_key] || {}).map do |name, data|
      Device.new(type: setting.to_s, name:, data: Data.wrap(data || {}))
    end
  end

  # All devices across all types
  def all_devices
    @all_devices ||= DEVICES.flat_map { |setting| devices_of(setting) }
  end

  # Create or update. For singletons, name defaults to setting.
  def update(setting, data, name: setting)
    yaml_key = YAML_KEYS[setting.to_s]
    raw = data.is_a?(Data) ? data.to_h : data
    if self.class.device?(setting)
      @data[yaml_key] ||= {}
      @data[yaml_key][name.to_s] = raw
    else
      @data[yaml_key] = raw
    end
    save!
  end

  def configured?(setting, name = nil)
    setting_data(setting, name).present?
  end

  # Add a new device
  def add(setting, name, data = {})
    unless self.class.device?(setting)
      raise ArgumentError, "#{setting} is not a device"
    end

    update(setting, data, name:)
  end

  # Remove a device
  def remove(setting, name)
    yaml_key = YAML_KEYS[setting.to_s]
    @data[yaml_key]&.delete(name.to_s)
    save!
  end

  # Check if any device uses MQTT as data source
  def mqtt_required?
    all_devices.any? do |d|
      d.data.data_source == 'mqtt' ||
        d.data.power_source == 'mqtt' ||
        d.data.details_source == 'mqtt'
    end
  end

  # Check if Ingest service is needed
  def ingest_required?
    inverters = devices_of('inverter')
    inverters.size > 1 ||
      inverters.any? { |d| d.data.house_power_known == false }
  end

  # Deduplicated SENEC hosts across all devices
  def senec_hosts
    all_devices.filter_map do |d|
      d.data.senec_host if d.data.data_source&.start_with?('senec')
    end.uniq
  end

  # Device names for each sensor
  def sensor_device_names
    sensor_defaults.device_names
  end

  # Default sensor mappings derived from device configuration
  def computed_sensor_mappings
    sensor_defaults.mappings
  end

  # Effective sensor mappings (computed + overrides from sensors section)
  def effective_sensor_mappings
    computed_sensor_mappings.merge(sensors)
  end

  def setup_completed?
    all_devices.any?
  end

  def save!
    dir = File.dirname(@path)
    FileUtils.mkdir_p(dir) unless File.directory?(dir)
    File.write(@path, YAML.dump(ordered_data))
    @all_devices = nil
    @sensor_defaults = nil
  end

  def ordered_data
    YAML_ORDER.each_with_object({}) do |key, hash|
      hash[key] = @data[key] if @data.key?(key)
    end
  end

  private

  def sensor_defaults
    @sensor_defaults ||= SensorDefaults.build(all_devices)
  end
end
