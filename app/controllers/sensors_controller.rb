class SensorsController < ApplicationController
  include SensorReadings

  def show
    @configuration = Configuration.current
    @sensor_mappings = @configuration.effective_sensor_mappings
    @device_names = @configuration.sensor_device_names
    @influxdb_running = influxdb_running?
    @readings = fetch_readings(configuration: @configuration, with_stats: true)
  end
end
