module Configurations
  class ReadingsController < ApplicationController
    include SensorReadings

    def index
      @configuration = Configuration.current
      @sensor_mappings = @configuration.effective_sensor_mappings
      @influxdb_running = influxdb_running?
      @readings = fetch_readings(configuration: @configuration)
    end
  end
end
