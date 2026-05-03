module Datasources
  module MqttTopics
    class ReadingsController < ApplicationController
      include SensorReadings

      def show
        @configuration = Configuration.current
        @readings = fetch_topic_readings(configuration: @configuration)
      end
    end
  end
end
