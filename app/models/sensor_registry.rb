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

  # Sensors Ingest consumes to recalculate house_power for balcony power plants
  # (mirrors INFLUX_SENSOR_* passed to the container, see
  # https://docs.solectrus.de/referenz/ingest/konfiguration/). A value written
  # straight to InfluxDB instead of through Ingest never enters this
  # recalculation, so the canonical list also decides where HELIOS explains the
  # Ingest endpoint to an external source (see
  # Configuration#external_ingest_inputs).
  INGEST_SENSORS = %w[
    inverter_power
    inverter_power_1 inverter_power_2 inverter_power_3 inverter_power_4 inverter_power_5
    grid_import_power grid_export_power
    battery_charging_power battery_discharging_power
    wallbox_power heatpump_power
    house_power
  ].freeze

  # The cars of an installation, numbered like the dashboard numbers them.
  # Car 1 reads the variables without a number (INFLUX_SENSOR_CAR_ODOMETER),
  # which every dashboard version accepts. Cars 2 to 5 carry their number
  # (INFLUX_SENSOR_CAR_ODOMETER_2).
  CAR_UNITS = {
    'car_battery_soc' => '%',
    'car_odometer' => 'km',
    'car_range' => 'km',
    'car_connected' => '',
    'car_latitude' => '°',
    'car_longitude' => '°',
  }.freeze
  CAR_SENSORS = (1..5).index_with do |number|
    CAR_UNITS.keys.map { |role| number == 1 ? role : "#{role}_#{number}" }.freeze
  end.freeze
  CAR_ROLES = CAR_SENSORS.values.flat_map { |sensors| sensors.zip(CAR_UNITS.keys) }.to_h.freeze

  # Sensors carrying a yes/no value instead of a numeric measurement. They have
  # no physical unit, so the UI shows a "yes/no" hint in place of the unit.
  BOOLEAN_SENSORS = [
    'system_status_ok',
    'wallbox_car_connected',
    *CAR_ROLES.filter_map { |name, role| name if role == 'car_connected' },
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
    **CAR_SENSORS.to_h { |number, sensors| [:"car_#{number}", sensors] },
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
    **CAR_ROLES.transform_values { |role| { unit: CAR_UNITS.fetch(role), sources: %w[mqtt external] } },

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

  # The sensor of a car without the number of the car, for example
  # car_odometer for car_odometer_2. nil for any other sensor.
  def self.car_role(sensor_name)
    CAR_ROLES[sensor_name]
  end

  def self.boolean?(sensor_name)
    BOOLEAN_SENSORS.include?(sensor_name)
  end

  # The data type a sensor is written to InfluxDB as. Every sensor carries
  # either a measurement, a yes/no answer or a status text, so nobody has to
  # decide this: a unit means a number, and BOOLEAN_SENSORS names the yes/no
  # ones among the unit-less rest. nil for a sensor this registry does not
  # know, which leaves a stored type untouched.
  def self.payload_type_for(sensor_name)
    return unless valid?(sensor_name)
    return 'boolean' if boolean?(sensor_name)

    unit_for(sensor_name).present? ? 'float' : 'string'
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
