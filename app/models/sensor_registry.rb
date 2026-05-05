class SensorRegistry
  # Available data sources for sensors
  SOURCES = %w[senec shelly mqtt forecast external].freeze

  # Sensors that can be flagged as a balcony power plant. A balcony generator
  # feeds directly into the home grid and distorts inverter-reported
  # house_power, so Ingest is required for correction.
  BALCONY_CAPABLE_SENSORS = %w[
    inverter_power_1
    inverter_power_2
    inverter_power_3
    inverter_power_4
    inverter_power_5
  ].freeze

  # Sensor groups for UI display
  GROUPS = {
    inverter: %w[
      inverter_power
      inverter_power_1
      inverter_power_2
      inverter_power_3
      inverter_power_4
      inverter_power_5
      case_temp
      system_status
      system_status_ok
    ],
    grid: %w[
      grid_import_power
      grid_export_power
      grid_export_limit
      house_power
    ],
    battery: %w[
      battery_charging_power
      battery_discharging_power
      battery_soc
    ],
    wallbox: %w[
      wallbox_power
      wallbox_car_connected
    ],
    car: %w[
      car_battery_soc
    ],
    heatpump: %w[
      heatpump_power
      heatpump_heating_power
      heatpump_tank_temp
      heatpump_tank_temp_setpoint
      heatpump_status
      outdoor_temp
    ],
    forecast: %w[
      inverter_power_forecast
      inverter_power_forecast_clearsky
      outdoor_temp_forecast
    ],
    custom: %w[
      custom_power_01
      custom_power_02
      custom_power_03
      custom_power_04
      custom_power_05
      custom_power_06
      custom_power_07
      custom_power_08
      custom_power_09
      custom_power_10
      custom_power_11
      custom_power_12
      custom_power_13
      custom_power_14
      custom_power_15
      custom_power_16
      custom_power_17
      custom_power_18
      custom_power_19
      custom_power_20
    ],
  }.freeze

  SENSORS = {
    # Inverter
    'inverter_power' => { unit: 'W', sources: %w[senec mqtt external] },
    'inverter_power_1' => { unit: 'W', sources: %w[senec shelly mqtt external] },
    'inverter_power_2' => { unit: 'W', sources: %w[senec shelly mqtt external] },
    'inverter_power_3' => { unit: 'W', sources: %w[senec shelly mqtt external] },
    'inverter_power_4' => { unit: 'W', sources: %w[shelly mqtt external] },
    'inverter_power_5' => { unit: 'W', sources: %w[shelly mqtt external] },

    # Grid
    'grid_import_power' => { unit: 'W', sources: %w[senec mqtt external] },
    'grid_export_power' => { unit: 'W', sources: %w[senec mqtt external] },
    'grid_export_limit' => { unit: '%', sources: %w[senec mqtt external] },
    'house_power' => { unit: 'W', sources: %w[senec mqtt external] },

    # Battery
    'battery_charging_power' => { unit: 'W', sources: %w[senec mqtt external] },
    'battery_discharging_power' => { unit: 'W', sources: %w[senec mqtt external] },
    'battery_soc' => { unit: '%', sources: %w[senec mqtt external] },

    # Wallbox
    'wallbox_power' => { unit: 'W', sources: %w[senec shelly mqtt external] },
    'wallbox_car_connected' => { unit: '', sources: %w[senec mqtt external] },

    # Car
    'car_battery_soc' => { unit: '%', sources: %w[mqtt external] },

    # Heatpump
    'heatpump_power' => { unit: 'W', sources: %w[shelly mqtt external] },
    'heatpump_heating_power' => { unit: 'W', sources: %w[mqtt external] },
    'heatpump_tank_temp' => { unit: '°C', sources: %w[mqtt external] },
    'heatpump_tank_temp_setpoint' => { unit: '°C', sources: %w[mqtt external] },
    'heatpump_status' => { unit: '', sources: %w[mqtt external] },

    # System
    'case_temp' => { unit: '°C', sources: %w[senec mqtt external] },
    'outdoor_temp' => { unit: '°C', sources: %w[mqtt external] },
    'system_status' => { unit: '', sources: %w[senec mqtt external] },
    'system_status_ok' => { unit: '', sources: %w[senec mqtt external] },

    # Forecast
    'inverter_power_forecast' => { unit: 'W', sources: %w[forecast external] },
    'inverter_power_forecast_clearsky' => { unit: 'W', sources: %w[forecast external] },
    'outdoor_temp_forecast' => { unit: '°C', sources: %w[forecast external] },

    # Custom
    'custom_power_01' => { unit: 'W', sources: %w[shelly mqtt external] },
    'custom_power_02' => { unit: 'W', sources: %w[shelly mqtt external] },
    'custom_power_03' => { unit: 'W', sources: %w[shelly mqtt external] },
    'custom_power_04' => { unit: 'W', sources: %w[shelly mqtt external] },
    'custom_power_05' => { unit: 'W', sources: %w[shelly mqtt external] },
    'custom_power_06' => { unit: 'W', sources: %w[shelly mqtt external] },
    'custom_power_07' => { unit: 'W', sources: %w[shelly mqtt external] },
    'custom_power_08' => { unit: 'W', sources: %w[shelly mqtt external] },
    'custom_power_09' => { unit: 'W', sources: %w[shelly mqtt external] },
    'custom_power_10' => { unit: 'W', sources: %w[shelly mqtt external] },
    'custom_power_11' => { unit: 'W', sources: %w[shelly mqtt external] },
    'custom_power_12' => { unit: 'W', sources: %w[shelly mqtt external] },
    'custom_power_13' => { unit: 'W', sources: %w[shelly mqtt external] },
    'custom_power_14' => { unit: 'W', sources: %w[shelly mqtt external] },
    'custom_power_15' => { unit: 'W', sources: %w[shelly mqtt external] },
    'custom_power_16' => { unit: 'W', sources: %w[shelly mqtt external] },
    'custom_power_17' => { unit: 'W', sources: %w[shelly mqtt external] },
    'custom_power_18' => { unit: 'W', sources: %w[shelly mqtt external] },
    'custom_power_19' => { unit: 'W', sources: %w[shelly mqtt external] },
    'custom_power_20' => { unit: 'W', sources: %w[shelly mqtt external] },
  }.freeze

  def self.unit_for(sensor_name)
    SENSORS.dig(sensor_name, :unit) || ''
  end

  def self.sources_for(sensor_name)
    SENSORS.dig(sensor_name, :sources) || []
  end

  def self.group_for(sensor_name)
    GROUPS.find { |_group, sensors| sensors.include?(sensor_name) }&.first
  end

  def self.sensors_in_group(group)
    GROUPS[group.to_sym] || []
  end

  def self.valid?(sensor_name)
    SENSORS.key?(sensor_name)
  end
end
