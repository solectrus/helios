module SensorRow
  module ValueCell
    class Component < ViewComponent::Base
      attr_reader :sensor_row

      delegate :sensor_name, :freshness_class, :timestamp_iso,
               :boolean_value?, :boolean_label, :formatted_value, :value?, :unit,
               :unit_label,
               to: :sensor_row

      def initialize(sensor_row:)
        super()
        @sensor_row = sensor_row
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
