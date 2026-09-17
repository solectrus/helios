module Export
  # Resolves where a service's "Open" link should point, or nil when the service
  # has no browsable endpoint. Returns either an absolute :url (built
  # server-side from the public domain, when behind a reverse proxy) or a :port
  # (opened client-side at the current hostname, so it works regardless of how
  # HELIOS itself is being accessed).
  #
  # Shared by the per-service "Open" button (ServiceRow) and the status bar's
  # prominent "Open dashboard" shortcut.
  #
  # A service whose published port is no web address gets no link. Each
  # service class says so itself (Services::Base.browsable?); a name HELIOS
  # does not manage keeps the link it has always had.
  class OpenEndpoint
    def self.resolve(service_name:, public_port:, configuration: Configuration.current)
      new(service_name:, public_port:, configuration:).resolve
    end

    def initialize(service_name:, public_port:, configuration:)
      @service_name = service_name
      @public_port = public_port
      @configuration = configuration
    end

    def resolve
      return unless browsable?

      url = PublicUrl.build(configuration, service_name)
      if url
        { url: }
      elsif public_port
        { port: public_port }
      end
    end

    private

    attr_reader :service_name, :public_port, :configuration

    def browsable?
      service_class = Compose.find_service(service_name)
      service_class.nil? || service_class.browsable?
    end
  end
end
