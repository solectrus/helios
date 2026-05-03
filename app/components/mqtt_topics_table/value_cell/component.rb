module MqttTopicsTable
  module ValueCell
    class Component < ViewComponent::Base
      attr_reader :index, :reading

      delegate :value?, :timestamp_iso, :freshness_class, to: :reading, allow_nil: true

      def initialize(index:, reading: nil)
        super()
        @index = index
        @reading = reading
      end

      def dom_id
        "mqtt-topic-value-#{index}"
      end

      def formatted_value
        reading&.formatted(precision: 2) || Reading::EMPTY_DISPLAY
      end
    end
  end
end
