module Surveys
  module Mqtt
    class Survey < Base
      private

      def customize!(data)
        apply_image_choices!(data, :MQTT_COLLECTOR)
      end
    end
  end
end
