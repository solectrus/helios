module Import
  class ConfigurationImporter
    # Mirrors SOLECTRUS's Sensor::LegacyConfigAdapter: pre-sensor-config stacks
    # set INFLUX_MEASUREMENT_PV / INFLUX_MEASUREMENT_FORECAST on the dashboard
    # and rely on the dashboard's internal fallback table to resolve each
    # sensor. HELIOS reproduces that table so imported configs reflect the
    # sensors the dashboard would actually serve.
    #
    # Older stacks (pre-2022) don't even set INFLUX_MEASUREMENT_PV/FORECAST and
    # let every component default to the collector's compiled-in measurement
    # name ('SENEC' / 'Forecast'). When a senec-collector or forecast-collector
    # is present in the imported stack, we fall back to its measurement so
    # those stacks still synthesize their sensors instead of round-tripping to
    # an empty `sensors: {}` (which would silently strip the collector on
    # re-export, since no sensor sourced it any more).
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

      # Per-measurement-key fallback when the dashboard env doesn't carry the
      # explicit INFLUX_MEASUREMENT_* var — supplied by the matching collector
      # extractor.
      COLLECTOR_MEASUREMENT_KEY = {
        'INFLUX_MEASUREMENT_PV' => :senec_measurement,
        'INFLUX_MEASUREMENT_FORECAST' => :forecast_measurement,
      }.freeze

      # Returns synthesized { sensor_name => "measurement:field" } for every
      # FALLBACK_SENSORS entry the legacy dashboard would resolve. Existing
      # INFLUX_SENSOR_* entries in the env win — callers merge on top, and
      # an explicit empty entry (`INFLUX_SENSOR_X=`) counts as "user opted
      # out", so we don't resurrect it through the fallback.
      # Returns {} when legacy markers are absent.
      def self.synthesize(dashboard_env, senec_measurement: nil, forecast_measurement: nil)
        collector_measurements = {
          senec_measurement: senec_measurement,
          forecast_measurement: forecast_measurement,
        }
        return {} unless legacy_mode?(dashboard_env, **collector_measurements)

        FALLBACK_SENSORS.each_with_object({}) do |(name, (measurement_key, field)), out|
          next if dashboard_env.key?("INFLUX_SENSOR_#{name.upcase}")

          measurement = resolve_measurement(measurement_key, dashboard_env, collector_measurements)
          next if measurement.blank?

          out[name] = "#{measurement}:#{field}"
        end
      end

      # Activate when the stack either advertises the legacy measurement vars
      # OR ships a SOLECTRUS collector whose default measurement we can fall
      # back to. The collector-only path is restricted to stacks that haven't
      # configured ANY INFLUX_SENSOR_* yet — once even one explicit mapping
      # exists the user has crossed into per-sensor configuration territory,
      # and HELIOS leaves them in full control. A completely empty sensor env
      # on a stack with no collectors stays "intentionally unconfigured", so
      # HELIOS doesn't conjure sensors out of thin air for fresh installs.
      def self.legacy_mode?(env, senec_measurement: nil, forecast_measurement: nil)
        return true if env['INFLUX_MEASUREMENT_PV'].present? || env['INFLUX_MEASUREMENT_FORECAST'].present?

        collector_present = senec_measurement.present? || forecast_measurement.present?
        collector_present && env.keys.none? { |k| k.start_with?('INFLUX_SENSOR_') }
      end

      def self.resolve_measurement(measurement_key, dashboard_env, collector_measurements)
        explicit = dashboard_env[measurement_key].presence
        return explicit if explicit

        collector_measurements[COLLECTOR_MEASUREMENT_KEY[measurement_key]]
      end
    end
  end
end
