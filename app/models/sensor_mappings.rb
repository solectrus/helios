# Derives InfluxDB measurement:field mappings from sensor configuration
class SensorMappings
  # Each mapping is [measurement, field].

  # SENEC collector mappings
  SENEC_DEFAULTS = {
    'inverter_power' => %w[SENEC inverter_power],
    'inverter_power_1' => %w[SENEC mpp1_power],
    'inverter_power_2' => %w[SENEC mpp2_power],
    'inverter_power_3' => %w[SENEC mpp3_power],
    'house_power' => %w[SENEC house_power],
    'grid_import_power' => %w[SENEC grid_power_plus],
    'grid_export_power' => %w[SENEC grid_power_minus],
    'battery_charging_power' => %w[SENEC bat_power_plus],
    'battery_discharging_power' => %w[SENEC bat_power_minus],
    'battery_soc' => %w[SENEC bat_fuel_charge],
    'case_temp' => %w[SENEC case_temp],
    'system_status' => %w[SENEC current_state],
    'system_status_ok' => %w[SENEC current_state_ok],
    'grid_export_limit' => %w[SENEC power_ratio],
    'wallbox_power' => %w[SENEC wallbox_charge_power],
    'wallbox_car_connected' => %w[SENEC ev_connected],
  }.freeze

  # Forecast collector mappings
  FORECAST_DEFAULTS = {
    'inverter_power_forecast' => %w[forecast watt],
    'inverter_power_forecast_clearsky' => %w[forecast watt_clearsky],
    'outdoor_temp_forecast' => %w[forecast temperature],
  }.freeze

  # Generic SOLECTRUS defaults, applied to any source that is not tied to a
  # specific collector (i.e. everything except senec/forecast).
  DEFAULTS = {
    # Inverter
    'inverter_power' => %w[inverter power],
    'inverter_power_1' => %w[inverter_1 power],
    'inverter_power_2' => %w[inverter_2 power],
    'inverter_power_3' => %w[inverter_3 power],
    'inverter_power_4' => %w[inverter_4 power],
    'inverter_power_5' => %w[inverter_5 power],

    # Forecast (when imported via external instead of the forecast collector)
    'inverter_power_forecast' => %w[inverter_forecast power],
    'inverter_power_forecast_clearsky' => %w[inverter_forecast_clearsky power],
    'outdoor_temp_forecast' => %w[outdoor_forecast temperature],

    # Grid / House
    'grid_import_power' => %w[grid import_power],
    'grid_export_power' => %w[grid export_power],
    'grid_export_limit' => %w[grid export_limit],
    'house_power' => %w[house power],

    # Battery
    'battery_charging_power' => %w[battery charging_power],
    'battery_discharging_power' => %w[battery discharging_power],
    'battery_soc' => %w[battery soc],

    # Wallbox
    'wallbox_power' => %w[wallbox power],
    'wallbox_car_connected' => %w[wallbox connected],

    # Car
    'car_battery_soc' => %w[car battery_soc],

    # Heatpump
    'heatpump_power' => %w[heatpump power],
    'heatpump_heating_power' => %w[heatpump heating_power],
    'heatpump_tank_temp' => %w[heatpump tank_temp],
    'heatpump_tank_temp_setpoint' => %w[heatpump tank_temp_setpoint],
    'heatpump_status' => %w[heatpump status],

    # System / Environment
    'case_temp' => %w[case temperature],
    'outdoor_temp' => %w[outdoor temperature],
    'system_status' => %w[system status],
    'system_status_ok' => %w[system status_ok],

    # Custom (01..20)
    **(1..20).to_h do |i|
      suffix = format('%02d', i)
      ["custom_power_#{suffix}", ["custom_#{suffix}", 'power']]
    end,
  }.freeze

  # Returns the default measurement for a sensor+source combination
  def self.default_measurement(sensor_name, source)
    case source
    when 'senec' then SENEC_DEFAULTS.dig(sensor_name, 0) || 'SENEC'
    when 'forecast' then FORECAST_DEFAULTS.dig(sensor_name, 0) || 'forecast'
    else DEFAULTS.dig(sensor_name, 0) || sensor_name
    end
  end

  # Returns the default field for a sensor+source combination
  def self.default_field(sensor_name, source)
    case source
    when 'senec' then SENEC_DEFAULTS.dig(sensor_name, 1) || sensor_name
    when 'forecast' then FORECAST_DEFAULTS.dig(sensor_name, 1) || 'value'
    else DEFAULTS.dig(sensor_name, 1) || 'value'
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
