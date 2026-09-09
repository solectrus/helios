module Surveys
  module Sensor
    # The MQTT pages of the sensor survey, as MqttPages fills them.
    #
    # Split off from Survey because it is a self-contained concern with its own
    # collaborators, the way MappingInjector handles the InfluxDB mapping page.
    class MqttInjector
      # Everything here belongs to source = mqtt alone, so MqttFields ANDs this
      # into every condition it generates.
      SOURCE = "{source} = 'mqtt'".freeze

      PAGES = {
        kind: 'p_mqtt_kind',
        extraction_method: 'p_mqtt_extraction',
        extraction_value: 'p_mqtt_extraction_value',
        filters: 'p_mqtt_filter',
        name: 'p_mqtt_name',
        write: 'p_mqtt_write',
      }.freeze

      def initialize(sensor_name)
        @sensor_name = sensor_name
      end

      def call(survey)
        MqttPages.new(fields:, key: [:sensor, sensor_name], pages: PAGES).call(survey)
      end

      private

      attr_reader :sensor_name

      # The sensor survey named two of its questions before the prefix
      # convention settled, so both keep their own names. The data type is not
      # among the questions: the sensor decides it, and only an entry stored
      # before that carries a type of its own.
      def fields
        MqttFields.new(
          prefix: 'mqtt_',
          guard: SOURCE,
          type_field: 'mqtt_payload_type',
          method_field: 'mqtt_extraction_mode',
          fixed_type: stored_type.presence || expected_type,
          expected_type:,
        )
      end

      def expected_type
        @expected_type ||= SensorRegistry.payload_type_for(sensor_name)
      end

      def stored_type
        Configuration.current.sensor_config(sensor_name).mqtt_payload_type.to_s
      end
    end
  end
end
