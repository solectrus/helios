module Export
  # Browsable HTTPS URL for a service when the stack runs behind a reverse
  # proxy. Returns nil when there is no reverse proxy, no configured domain, or
  # the service is not routed — the caller then falls back to a direct host port
  # (built client-side at the current hostname) or shows no button.
  #
  # `published:` tells whether the service publishes a host port. In external
  # mode only published services are reachable through the proxy, so the flag
  # gates that branch.
  class PublicUrl
    def self.build(configuration, service_name, published:)
      new(configuration).build(service_name, published:)
    end

    def initialize(configuration)
      @configuration = configuration
    end

    def build(service_name, published:)
      if configuration.reverse_proxy_managed?
        managed(service_name)
      elsif configuration.reverse_proxy_external? && published
        external(service_name)
      end
    end

    private

    attr_reader :configuration

    # Managed Traefik (HELIOS-owned): the dashboard is routed at the domain
    # root, an exposed InfluxDB on a dedicated entrypoint (its own port). Other
    # services keep their published host ports and get no domain URL here.
    def managed(service_name)
      domain = configuration.reverse_proxy.app_domain

      case service_name
      when 'dashboard'
        "https://#{domain}"
      when 'influxdb'
        if Services::Influxdb.exposed?(configuration)
          "https://#{domain}:#{Services::Influxdb.host_port(configuration)}"
        end
      end
    end

    # External Traefik: the user's proxy routes each published service on a
    # subdomain of app_host over HTTPS (dashboard on the bare host) — see
    # TraefikConfig::ROUTABLE. Without a configured app_host there is no real
    # domain to link to.
    def external(service_name)
      host = configuration.system.app_host.presence
      return unless host

      entry = TraefikConfig::ROUTABLE.find { |e| e[:klass].service_name == service_name }
      return unless entry

      subdomain = entry[:subdomain]
      subdomain ? "https://#{subdomain}.#{host}" : "https://#{host}"
    end
  end
end
