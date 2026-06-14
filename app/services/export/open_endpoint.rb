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
  # Traefik is excluded: it is the reverse proxy, its published 80/443 ports are
  # not a destination of their own.
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
      return if service_name == 'traefik'

      url = PublicUrl.build(configuration, service_name, published: public_port.present?)
      if url
        { url: }
      elsif public_port
        { port: public_port }
      end
    end

    private

    attr_reader :service_name, :public_port, :configuration
  end
end
