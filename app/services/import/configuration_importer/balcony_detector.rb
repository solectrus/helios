module Import
  class ConfigurationImporter
    # A balcony generator feeds a different InfluxDB measurement (e.g.
    # `Garage:`, `Fence:`) than the main roof inverter, so its output distorts
    # inverter-reported house_power and needs Ingest to recalculate it.
    #
    # Every populated `inverter_power_N` slot whose measurement differs from the
    # main inverter's is its own balcony generator — a user can run several
    # (e.g. two fence-mounted plants on `Fence1:`/`Fence2:`). Multiple slots
    # sharing the main inverter's measurement are its MPPT strings (e.g. SENEC
    # V3), not balcony generators. With a single populated slot the user is
    # treated as balcony-only.
    class BalconyDetector
      include Helpers

      def initialize(reader, sensors_data)
        @reader = reader
        @sensors_data = sensors_data
      end

      # All inverter slots that represent a balcony generator (may be empty).
      def sensor_names
        @sensor_names ||= detect
      end

      def split_inverter_present?
        @reader.services.key?('ingest') && populated_balcony_sensors.any?
      end

      private

      def detect
        return [] unless split_inverter_present?

        # Single populated slot → balcony-only; the lone inverter is the balcony.
        return populated_balcony_sensors if populated_balcony_sensors.one?

        # All slots share one measurement → MPPT strings of one inverter.
        return [] if populated_measurements.one?

        # Several measurements: the main inverter is the lowest-indexed slot's
        # measurement; every slot on a different measurement is a balcony.
        populated_balcony_sensors.reject { |name| sensor_measurement(name) == main_measurement }
      end

      def main_measurement
        sensor_measurement(populated_balcony_sensors.first)
      end

      def populated_measurements
        populated_balcony_sensors.map { |name| sensor_measurement(name) }.uniq
      end

      def populated_balcony_sensors
        @populated_balcony_sensors ||=
          SensorRegistry::BALCONY_CAPABLE_SENSORS.select { |name| @sensors_data[name].present? }
      end
    end
  end
end
