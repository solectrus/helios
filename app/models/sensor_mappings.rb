# Derives InfluxDB measurement:field mappings from sensor configuration
class SensorMappings
  # Default SENEC measurement:field mappings
  SENEC_DEFAULTS = {
    'inverter_power' => { measurement: 'SENEC', field: 'inverter_power' },
    'inverter_power_1' => { measurement: 'SENEC', field: 'mpp1_power' },
    'inverter_power_2' => { measurement: 'SENEC', field: 'mpp2_power' },
    'inverter_power_3' => { measurement: 'SENEC', field: 'mpp3_power' },
    'house_power' => { measurement: 'SENEC', field: 'house_power' },
    'grid_import_power' => { measurement: 'SENEC', field: 'grid_power_plus' },
    'grid_export_power' => { measurement: 'SENEC', field: 'grid_power_minus' },
    'battery_charging_power' => { measurement: 'SENEC', field: 'bat_power_plus' },
    'battery_discharging_power' => { measurement: 'SENEC', field: 'bat_power_minus' },
    'battery_soc' => { measurement: 'SENEC', field: 'bat_fuel_charge' },
    'case_temp' => { measurement: 'SENEC', field: 'case_temp' },
    'system_status' => { measurement: 'SENEC', field: 'current_state' },
    'system_status_ok' => { measurement: 'SENEC', field: 'current_state_ok' },
    'grid_export_limit' => { measurement: 'SENEC', field: 'power_ratio' },
    'wallbox_power' => { measurement: 'SENEC', field: 'wallbox_charge_power' },
    'wallbox_car_connected' => { measurement: 'SENEC', field: 'ev_connected' },
  }.freeze

  FORECAST_DEFAULTS = {
    'inverter_power_forecast' => { measurement: 'Forecast', field: 'watt' },
    'inverter_power_forecast_clearsky' => { measurement: 'Forecast', field: 'watt_clearsky' },
    'outdoor_temp_forecast' => { measurement: 'Forecast', field: 'temperature' },
  }.freeze

  # Returns the default measurement for a sensor+source combination
  def self.default_measurement(sensor_name, source)
    case source
    when 'senec' then SENEC_DEFAULTS.dig(sensor_name, :measurement) || 'SENEC'
    when 'forecast' then FORECAST_DEFAULTS.dig(sensor_name, :measurement) || 'Forecast'
    else sensor_name
    end
  end

  # Returns the default field for a sensor+source combination
  def self.default_field(sensor_name, source)
    case source
    when 'senec' then SENEC_DEFAULTS.dig(sensor_name, :field) || sensor_name
    when 'forecast' then FORECAST_DEFAULTS.dig(sensor_name, :field) || 'value'
    when 'shelly' then 'power'
    else 'value'
    end
  end

  # Returns the InfluxDB mapping string for a given sensor and its config
  def self.mapping_for(sensor_name, config)
    source = config.source.to_s
    return nil if source.blank?

    measurement = config['measurement'].presence || default_measurement(sensor_name, source)
    field = config['field'].presence || default_field(sensor_name, source)

    "#{measurement}:#{field}"
  end
end
