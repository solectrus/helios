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

      private

      # Empty on the server: the age is relative to the reader's clock, so the
      # controller writes it once it runs.
      def age_hint
        tag.span(
          data: {
            controller: 'relative-time',
            relative_time_datetime_value: timestamp_iso,
            relative_time_target_value: 'text',
          },
        )
      end
    end
  end
end
