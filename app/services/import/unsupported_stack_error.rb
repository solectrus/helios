module Import
  # Raised by CompatibilityCheck when an imported compose stack holds something
  # HELIOS cannot reproduce: a service whose image it does not recognize, or a
  # Docker network it would not write again. Carries both so the UI can list
  # what stands in the way.
  class UnsupportedStackError < StandardError
    # Array of { 'service' => name, 'image' => image }.
    attr_reader :services

    # Array of network names.
    attr_reader :networks

    def initialize(services, networks)
      @services = services
      @networks = networks
      super("Unsupported stack: #{(services.pluck('service') + networks).join(', ')}")
    end
  end
end
