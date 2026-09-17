module Surveys
  module Mqtt
    class Survey < Base
      private

      def customize!(data)
        preselect_broker_kind!(data)
      end

      # `broker_external` is a UI-only question, never stored: which kind of
      # broker runs follows from `mqtt.broker_managed`. SurveyJS falls back to
      # the default whenever the prefill carries no value, so the default is
      # what preselects the answer. A foreign broker is the norm, and the one
      # every configuration without the flag has.
      def preselect_broker_kind!(data)
        element = find_element(data, 'broker_external')
        return unless element

        element['defaultValue'] = !configuration.mqtt_broker_managed?
      end

      def configuration
        @configuration ||= Configuration.current
      end
    end
  end
end
