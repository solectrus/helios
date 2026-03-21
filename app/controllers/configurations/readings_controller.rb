module Configurations
  class ReadingsController < ApplicationController
    include SensorReadings

    def index
      @configuration = Configuration.current
      @readings = fetch_readings(configuration: @configuration)
    end
  end
end
