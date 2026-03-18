module Sensors
  class ReadingsController < ApplicationController
    include SensorReadings

    def index
      configuration = Configuration.current
      @sensor_mappings = configuration.effective_sensor_mappings
      @device_names = configuration.sensor_device_names
      @influxdb_running = influxdb_running?
      @readings = fetch_readings(configuration:)
    end
  end
end
