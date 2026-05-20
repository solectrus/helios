module Import
  class ConfigurationImporter
    class SensorsExtractor
      include Helpers

      def initialize(reader, senec_measurement: nil, forecast_measurement: nil)
        @reader = reader
        @senec_measurement = senec_measurement
        @forecast_measurement = forecast_measurement
      end

      def sensors_data
        @sensors_data ||= begin
          dashboard_env = service_env('dashboard')
          # Read INFLUX_SENSOR_* from the dashboard's interpolated env (covers
          # inline `- INFLUX_SENSOR_X=value` definitions plus `${VAR}` refs
          # resolved through compose) AND from `.env` directly, so an orphan
          # mapping defined in `.env` but never listed in
          # `dashboard.environment:` still imports as a sensor — a collector
          # may already be writing the measurement (e.g. an appliance-named
          # shelly-collector) and dropping the sensor would silently hide
          # that data. Dashboard side wins for shared keys (its values are
          # interpolated, raw_env still carries `${VAR}` literals), and
          # orphans from `.env` are appended after the dashboard-ordered
          # entries to stabilize downstream ID assignment (MQTT MAPPING_x).
          explicit = collect_sensor_mappings(dashboard_env)
                     .merge(collect_sensor_mappings(@reader.raw_env.to_h)) { |_, dash_value, _| dash_value }
          # Legacy stacks omit most INFLUX_SENSOR_* and rely on the dashboard's
          # built-in fallback table — replicate it so the imported config matches
          # what the dashboard actually serves. Pre-INFLUX_MEASUREMENT_PV stacks
          # fall back to the collectors' compiled-in measurement defaults.
          synthesized = LegacySensorAdapter.synthesize(
            dashboard_env,
            senec_measurement: @senec_measurement,
            forecast_measurement: @forecast_measurement,
          )
          synthesized.merge(explicit).select { |name, _| SensorRegistry.valid?(name) }
        end
      end

      def excluded_sensor_names
        csv_split(service_env('dashboard')['INFLUX_EXCLUDE_FROM_HOUSE_POWER']).map(&:downcase)
      end

      private

      # Filter to well-formed `measurement:field` mappings only, then strip the
      # INFLUX_SENSOR_ prefix and downcase the keys. Drops blank entries and
      # literal placeholders (e.g. `=false`, `=0`) that some stacks use to stub
      # disabled sensors before the dashboard manages them as DB settings.
      def collect_sensor_mappings(env)
        env.select { |k, _| k.start_with?('INFLUX_SENSOR_') }
           .compact_blank
           .select { |_, v| well_formed_mapping?(v) }
           .transform_keys { |k| k.delete_prefix('INFLUX_SENSOR_').downcase }
      end

      def well_formed_mapping?(value)
        measurement, field = value.to_s.split(':', 2)
        measurement.present? && field.present?
      end
    end
  end
end
