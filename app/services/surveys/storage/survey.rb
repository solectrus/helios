module Surveys
  module Storage
    class Survey < Base
      private

      # The broker exists only while HELIOS runs one, so its row would name a
      # folder that no service fills.
      def customize!(data)
        return if Configuration.current.mqtt_broker_managed?

        remove_element(data, 'mosquitto')
      end
    end
  end
end
