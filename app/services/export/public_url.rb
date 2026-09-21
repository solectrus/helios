module Export
  # Browsable HTTPS URL for a service when the stack runs behind a reverse
  # proxy. Returns nil when there is no reverse proxy, no configured domain, or
  # the service is not routed — the caller then falls back to a direct host
  # port (built client-side at the current hostname) or shows no button.
  #
  # Which services are routed is asked of Compose::EXTERNALLY_ROUTABLE, not of
  # the published ports: on a shared Docker network a routed service publishes
  # nothing at all, and an InfluxDB kept inside the stack publishes a port for
  # the local network without being routed.
  class PublicUrl
    def self.build(configuration, service_name)
      new(configuration).build(service_name)
    end

    def initialize(configuration)
      @configuration = configuration
    end

    def build(service_name)
      if configuration.reverse_proxy_managed?
        managed(service_name)
      elsif configuration.reverse_proxy_external?
        external(service_name)
      end
    end

    private

    attr_reader :configuration

    # Managed Traefik (HELIOS-owned): the dashboard is routed at the domain
    # root, an exposed InfluxDB and HELIOS each on a dedicated entrypoint
    # (their own port). Other services keep their published host ports and get
    # no domain URL here.
    def managed(service_name)
      domain = configuration.public_host

      case service_name
      when 'dashboard'
        "https://#{domain}"
      when 'influxdb'
        if Services::Influxdb.exposed?(configuration)
          "https://#{domain}:#{Services::Influxdb.host_port(configuration)}"
        end
      when 'helios'
        "https://#{domain}:#{Services::Helios::HOST_PORT}"
      end
    end

    # External proxy: it routes each service on a subdomain of app_host over
    # HTTPS, the dashboard on the bare host. Without a configured app_host
    # there is no real domain to link to.
    def external(service_name)
      host = configuration.public_host
      return unless host

      klass = Compose.externally_routable(configuration).find { |candidate| candidate.service_name == service_name }
      return unless klass

      subdomain = klass.proxy_subdomain
      subdomain ? "https://#{subdomain}.#{host}" : "https://#{host}"
    end
  end
end
