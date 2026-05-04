module Import
  class ConfigurationImporter
    class SensorsExtractor
      include Helpers

      def initialize(reader)
        @reader = reader
      end

      def sensors_data
        @sensors_data ||= begin
          dashboard_env = service_env('dashboard')
          explicit = dashboard_env
                     .select { |k, _| k.start_with?('INFLUX_SENSOR_') }
                     .compact_blank
                     .transform_keys { |k| k.delete_prefix('INFLUX_SENSOR_').downcase }
          # Legacy stacks omit most INFLUX_SENSOR_* and rely on the dashboard's
          # built-in fallback table — replicate it so the imported config matches
          # what the dashboard actually serves.
          LegacySensorAdapter.synthesize(dashboard_env).merge(explicit)
                             .select { |name, _| SensorRegistry.valid?(name) }
        end
      end

      def excluded_sensor_names
        csv_split(service_env('dashboard')['INFLUX_EXCLUDE_FROM_HOUSE_POWER']).map(&:downcase)
      end
    end
  end
end
