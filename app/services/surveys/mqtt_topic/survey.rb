module Surveys
  module MqttTopic
    # The standalone MQTT mapping survey, whose pages MqttPages fills from the
    # shared MqttFields fragments.
    class Survey < Base
      PAGES = {
        kind: 'p_kind',
        extraction_method: 'p_extraction_method',
        extraction_value: 'p_extraction_value',
        filters: 'p_filters',
        name: 'p_name',
        write: 'p_write',
      }.freeze

      private

      def customize!(data)
        # Only a standalone entry may skip writing: a sensor names an InfluxDB
        # target by definition.
        MqttPages.new(fields: MqttFields.new(skip_write: true), key: [:topic, index], pages: PAGES).call(data)
      end
    end
  end
end
