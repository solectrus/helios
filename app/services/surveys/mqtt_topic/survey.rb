module Surveys
  module MqttTopic
    # Pulls the shared MQTT extraction-mode + filter elements from
    # MqttFields into the page placeholders defined in survey.json.
    class Survey < Base
      private

      def customize!(data)
        fields = MqttFields.new

        find_page(data, 'p_extraction_method')['elements'] = [fields.extraction_method_radio]
        find_page(data, 'p_extraction_value')['elements'] = [*fields.extraction_value_inputs, fields.type_dropdown]
        find_page(data, 'p_filters')['elements'] = fields.filter_inputs
      end
    end
  end
end
