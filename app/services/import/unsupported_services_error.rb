module Import
  # Raised by CompatibilityCheck when an imported compose stack contains a
  # service whose image HELIOS does not recognize. Carries the offending
  # services so the UI can list them for the user.
  class UnsupportedServicesError < StandardError
    # Array of { 'service' => name, 'image' => image }.
    attr_reader :services

    def initialize(services)
      @services = services
      super("Unsupported services: #{services.pluck('service').join(', ')}")
    end
  end
end
