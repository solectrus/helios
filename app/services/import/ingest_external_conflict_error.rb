module Import
  # Raised when an imported stack runs Ingest but at least one Ingest input
  # arrives via an external source. HELIOS routes every Ingest input through
  # the proxy and cannot reroute a writer it does not manage, so it would drop
  # Ingest and silently lose the house_power correction (see
  # Configuration#ingest_required?). The import is refused so the user decides
  # whether Ingest is still needed. Carries the offending sensor names.
  class IngestExternalConflictError < StandardError
    # Array of sensor names (e.g. %w[inverter_power_2]).
    attr_reader :sensors

    def initialize(sensors)
      @sensors = sensors
      super("Ingest inputs from an external source: #{sensors.join(', ')}")
    end
  end
end
