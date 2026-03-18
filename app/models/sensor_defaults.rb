class SensorDefaults
  # Default sensor mappings for SENEC inverters (V3/V2.1 and Home 4)
  SENEC = {
    'inverter_power' => 'SENEC:inverter_power',
    'inverter_power_1' => 'SENEC:mpp1_power',
    'inverter_power_2' => 'SENEC:mpp2_power',
    'inverter_power_3' => 'SENEC:mpp3_power',
    'house_power' => 'SENEC:house_power',
    'grid_import_power' => 'SENEC:grid_power_plus',
    'grid_export_power' => 'SENEC:grid_power_minus',
    'battery_charging_power' => 'SENEC:bat_power_plus',
    'battery_discharging_power' => 'SENEC:bat_power_minus',
    'battery_soc' => 'SENEC:bat_fuel_charge',
    'case_temp' => 'SENEC:case_temp',
    'system_status' => 'SENEC:current_state',
    'system_status_ok' => 'SENEC:current_state_ok',
    'grid_export_limit' => 'SENEC:power_ratio',
  }.freeze

  VENDOR_MAPPINGS = {
    'senec3' => SENEC,
    'senec4' => SENEC,
  }.freeze

  # Sensor name for each device type when using Shelly
  SHELLY_SENSOR_BY_TYPE = {
    'heatpump' => 'heatpump_power',
    'wallbox' => 'wallbox_power',
  }.freeze

  Result = Struct.new(:mappings, :device_names)

  def self.for_devices(devices)
    build(devices).mappings
  end

  def self.device_names_for_devices(devices)
    build(devices).device_names
  end

  def self.build(devices)
    mappings = {}
    names = {}
    process_inverter_devices(devices, mappings, names)
    process_shelly_devices(devices, mappings, names)
    Result.new(mappings:, device_names: names)
  end

  def self.process_inverter_devices(devices, mappings, names)
    devices.select { |d| d.type == 'inverter' }.each do |device|
      vendor_defaults = VENDOR_MAPPINGS[device.data.battery_vendor]
      next unless vendor_defaults

      vendor_defaults.each do |sensor, mapping|
        mappings[sensor] ||= mapping
        names[sensor] ||= device.data.name || device.name
      end
    end
  end

  def self.process_shelly_devices(devices, mappings, names)
    consumer_index = 0

    devices.each do |device|
      next unless StackBuilder::Services::ShellyCollector.shelly?(device.data)

      sensor = shelly_sensor_name(device, consumer_index)
      next unless sensor

      consumer_index += 1 if device.type == 'consumer'
      mappings[sensor] ||= "#{device.name}:power"
      names[sensor] ||= device.data.name || device.name
    end
  end

  def self.shelly_sensor_name(device, consumer_index)
    if device.type == 'consumer'
      format('custom_power_%02d', consumer_index + 1)
    else
      SHELLY_SENSOR_BY_TYPE[device.type]
    end
  end

  private_class_method :process_inverter_devices,
                       :process_shelly_devices, :shelly_sensor_name
end
