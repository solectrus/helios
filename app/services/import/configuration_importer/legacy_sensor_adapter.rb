module Import
  class ConfigurationImporter
    # Mirrors SOLECTRUS's Sensor::LegacyConfigAdapter: pre-sensor-config stacks
    # set INFLUX_MEASUREMENT_PV / INFLUX_MEASUREMENT_FORECAST on the dashboard
    # and rely on the dashboard's internal fallback table to resolve each
    # sensor. HELIOS reproduces that table so imported configs reflect the
    # sensors the dashboard would actually serve.
    module LegacySensorAdapter
      # sensor_name => [measurement_env_var, field_name]
      FALLBACK_SENSORS = {
        'inverter_power' => %w[INFLUX_MEASUREMENT_PV inverter_power],
        'inverter_power_forecast' => %w[INFLUX_MEASUREMENT_FORECAST watt],
        'house_power' => %w[INFLUX_MEASUREMENT_PV house_power],
        'grid_import_power' => %w[INFLUX_MEASUREMENT_PV grid_power_plus],
        'grid_export_power' => %w[INFLUX_MEASUREMENT_PV grid_power_minus],
        'grid_export_limit' => %w[INFLUX_MEASUREMENT_PV power_ratio],
        'battery_charging_power' => %w[INFLUX_MEASUREMENT_PV bat_power_plus],
        'battery_discharging_power' => %w[INFLUX_MEASUREMENT_PV bat_power_minus],
        'battery_soc' => %w[INFLUX_MEASUREMENT_PV bat_fuel_charge],
        'wallbox_power' => %w[INFLUX_MEASUREMENT_PV wallbox_charge_power],
        'case_temp' => %w[INFLUX_MEASUREMENT_PV case_temp],
        'system_status' => %w[INFLUX_MEASUREMENT_PV current_state],
        'system_status_ok' => %w[INFLUX_MEASUREMENT_PV current_state_ok],
      }.freeze

      # Returns synthesized { sensor_name => "measurement:field" } for every
      # FALLBACK_SENSORS entry the legacy dashboard would resolve. Existing
      # INFLUX_SENSOR_* entries in the env win — callers merge on top, and
      # an explicit empty entry (`INFLUX_SENSOR_X=`) counts as "user opted
      # out", so we don't resurrect it through the fallback.
      # Returns {} when legacy markers are absent.
      def self.synthesize(dashboard_env)
        return {} unless legacy_mode?(dashboard_env)

        FALLBACK_SENSORS.each_with_object({}) do |(name, (measurement_key, field)), out|
          next if dashboard_env.key?("INFLUX_SENSOR_#{name.upcase}")

          measurement = dashboard_env[measurement_key].presence
          next if measurement.blank?

          out[name] = "#{measurement}:#{field}"
        end
      end

      # Only activate when the stack explicitly advertises the legacy
      # measurement vars. A completely empty sensor env is treated as
      # "intentionally unconfigured" rather than legacy, so HELIOS doesn't
      # conjure sensors out of thin air for fresh installs.
      def self.legacy_mode?(env)
        env['INFLUX_MEASUREMENT_PV'].present? || env['INFLUX_MEASUREMENT_FORECAST'].present?
      end
    end
  end
end
