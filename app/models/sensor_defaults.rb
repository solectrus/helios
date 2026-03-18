class SensorDefaults
  # Default sensor mappings for SENEC inverters (V3/V2.1 and Home 4)
  SENEC = {
    'INFLUX_SENSOR_INVERTER_POWER' => 'SENEC:inverter_power',
    'INFLUX_SENSOR_INVERTER_POWER_1' => 'SENEC:mpp1_power',
    'INFLUX_SENSOR_INVERTER_POWER_2' => 'SENEC:mpp2_power',
    'INFLUX_SENSOR_INVERTER_POWER_3' => 'SENEC:mpp3_power',
    'INFLUX_SENSOR_HOUSE_POWER' => 'SENEC:house_power',
    'INFLUX_SENSOR_GRID_IMPORT_POWER' => 'SENEC:grid_power_plus',
    'INFLUX_SENSOR_GRID_EXPORT_POWER' => 'SENEC:grid_power_minus',
    'INFLUX_SENSOR_BATTERY_CHARGING_POWER' => 'SENEC:bat_power_plus',
    'INFLUX_SENSOR_BATTERY_DISCHARGING_POWER' => 'SENEC:bat_power_minus',
    'INFLUX_SENSOR_BATTERY_SOC' => 'SENEC:bat_fuel_charge',
    'INFLUX_SENSOR_CASE_TEMP' => 'SENEC:case_temp',
    'INFLUX_SENSOR_SYSTEM_STATUS' => 'SENEC:current_state',
    'INFLUX_SENSOR_SYSTEM_STATUS_OK' => 'SENEC:current_state_ok',
    'INFLUX_SENSOR_GRID_EXPORT_LIMIT' => 'SENEC:power_ratio',
  }.freeze

  VENDOR_MAPPINGS = {
    'senec3' => SENEC,
    'senec4' => SENEC,
  }.freeze

  # Sensor name for each device kind when using Shelly
  SHELLY_SENSOR_BY_KIND = {
    'heatpump' => 'INFLUX_SENSOR_HEATPUMP_POWER',
    'wallbox' => 'INFLUX_SENSOR_WALLBOX_POWER',
  }.freeze

  Result = Struct.new(:mappings, :device_names)

  def self.for_chapters(chapters)
    build(chapters).mappings
  end

  def self.device_names_for_chapters(chapters)
    build(chapters).device_names
  end

  def self.build(chapters)
    mappings = {}
    names = {}
    process_inverter_chapters(chapters, mappings, names)
    process_shelly_chapters(chapters, mappings, names)
    Result.new(mappings:, device_names: names)
  end

  def self.process_inverter_chapters(chapters, mappings, names)
    chapters.select { |c| c.kind == 'inverter' }.each do |chapter|
      vendor_defaults = VENDOR_MAPPINGS[chapter.data['battery_vendor']]
      next unless vendor_defaults

      vendor_defaults.each do |sensor, mapping|
        mappings[sensor] ||= mapping
        names[sensor] ||= chapter.name
      end
    end
  end

  def self.process_shelly_chapters(chapters, mappings, names)
    consumer_index = 0

    chapters.each do |chapter|
      next unless chapter.shelly?

      measurement = chapter.data['identifier']
      next if measurement.blank?

      sensor = shelly_sensor_name(chapter, consumer_index)
      next unless sensor

      consumer_index += 1 if chapter.kind == 'consumer'
      mappings[sensor] ||= "#{measurement}:power"
      names[sensor] ||= chapter.name
    end
  end

  def self.shelly_sensor_name(chapter, consumer_index)
    if chapter.kind == 'consumer'
      format('INFLUX_SENSOR_CUSTOM_POWER_%02d', consumer_index + 1)
    else
      SHELLY_SENSOR_BY_KIND[chapter.kind]
    end
  end

  private_class_method :build, :process_inverter_chapters,
                       :process_shelly_chapters, :shelly_sensor_name
end
