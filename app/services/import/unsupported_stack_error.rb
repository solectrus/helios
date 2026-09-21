module Import
  # Raised by CompatibilityCheck when an imported compose stack holds something
  # HELIOS cannot reproduce: a service whose image it does not recognize, a
  # Docker network it would not write again, or a Traefik label it would
  # replace with one of its own. Carries all three so the UI can list what
  # stands in the way.
  class UnsupportedStackError < StandardError
    # Array of { 'service' => name, 'image' => image }.
    attr_reader :services

    # Array of network names.
    attr_reader :networks

    # Array of { 'service' => name, 'label' => label }.
    attr_reader :routing

    def initialize(services, networks, routing = [])
      @services = services
      @networks = networks
      @routing = routing
      named = services.pluck('service') + networks + routing.pluck('label')
      super("Unsupported stack: #{named.join(', ')}")
    end
  end
end
