class ConfigurationsController < ApplicationController
  include SensorReadings

  def show
    @configuration = Configuration.current
    @sensor_mappings = @configuration.effective_sensor_mappings
    @influxdb_running = influxdb_running?
    @readings = fetch_readings(configuration: @configuration)
  end
end
