module Sensors
  class ReadingsController < ApplicationController
    include SensorReadings

    def show
      @configuration = Configuration.current
      @readings = fetch_readings(configuration: @configuration)
    end
  end
end
