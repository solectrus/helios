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
    end
  end
end
