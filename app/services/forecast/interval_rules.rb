module Forecast
  # Provider-specific handling of FORECAST_INTERVAL.
  #
  # pvnode ignores the variable at runtime — the collector schedules pulls
  # itself based on the provider's update cadence — so HELIOS drops any
  # imported value and never emits the variable on export.
  #
  # solcast and forecast.solar use the variable directly; HELIOS passes
  # operator-supplied values through unchanged and falls back to a 900s
  # baseline on export when no value is set. The operator is expected to
  # match this to their API plan's limits — there is no clamping in
  # either direction.
  #
  # Source: https://docs.solectrus.de/referenz/forecast-collector/
  module IntervalRules
    EXPORT_DEFAULT = '900'.freeze

    module_function

    # Returns the value to store in config.yaml for the given input, or
    # nil if the variable should be dropped (pvnode, or blank).
    def normalize(provider:, interval:)
      return nil if provider == 'pvnode'
      return nil if interval.blank?

      interval
    end

    # Returns the value to emit on export, or nil if the variable should
    # be omitted entirely (pvnode always; otherwise the operator's value
    # or the 900s baseline).
    def emit_value(provider:, interval:)
      return nil if provider == 'pvnode'

      interval.presence || EXPORT_DEFAULT
    end
  end
end
