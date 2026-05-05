module Import
  class ConfigurationImporter
    # A balcony generator feeds a different InfluxDB measurement (e.g.
    # `Garage:`, `anker-akku:`) than the main roof inverter. The
    # highest-numbered populated slot wins; with a single populated slot the
    # user is treated as balcony-only.
    #
    # Multiple `inverter_power_N` slots sharing a single InfluxDB measurement
    # are the MPPTs of one multi-string inverter (e.g. SENEC V3), not a
    # separate balcony generator.
    class BalconyDetector
      def initialize(reader, sensors_data)
        @reader = reader
        @sensors_data = sensors_data
      end

      def sensor_name
        @sensor_name ||= detect
      end

      def split_inverter_present?
        @reader.services.key?('ingest') && populated_balcony_sensors.any?
      end

      private

      def detect
        return nil unless split_inverter_present?
        return nil if mppt_only?

        populated_balcony_sensors.last
      end

      def mppt_only?
        populated_balcony_sensors.size > 1 && populated_measurements.size == 1
      end

      def populated_measurements
        populated_balcony_sensors.map { |name| @sensors_data[name].to_s.split(':', 2).first }.uniq
      end

      def populated_balcony_sensors
        @populated_balcony_sensors ||=
          SensorRegistry::BALCONY_CAPABLE_SENSORS.select { |name| @sensors_data[name].present? }
      end
    end
  end
end
