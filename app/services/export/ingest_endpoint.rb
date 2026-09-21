module Export
  # Address an external source has to write to while Ingest runs. Ingest speaks
  # the InfluxDB write API, so such a source only has to swap the address; token
  # and bucket stay the same. A source that keeps writing to InfluxDB is missing
  # from the house_power recalculation, and Ingest then writes no house_power at
  # all (see Configuration#ingest_required?).
  #
  # Both reverse-proxy modes put TLS in front of the address, each in the shape
  # its proxy takes: the managed Traefik answers the domain of the stack on a
  # dedicated entrypoint, an external one routes a subdomain of it. Without a
  # proxy the address is the host port, in the clear.
  #
  # Returns nil when nothing in the configuration names the machine: app_host is
  # required only behind a reverse proxy, and it stays empty wherever HELIOS is
  # only ever reached at a loopback address, which the field refuses. A caller
  # then names the port alone instead of showing an address with a placeholder
  # in it.
  #
  # The address arrives as HostAddress stored it, the host alone, so this class
  # only has to put brackets around an IPv6 address before the port.
  class IngestEndpoint
    PORT = Services::Ingest::PORT

    def self.url(configuration = Configuration.current)
      new(configuration).url
    end

    def initialize(configuration)
      @configuration = configuration
    end

    def url
      return unless host

      return "https://ingest.#{host}" if configuration.reverse_proxy_external?
      return "https://#{host}:#{PORT}" if Services::Ingest.traefik_managed_routing?(configuration)

      "http://#{HostAddress.for_url(host)}:#{PORT}"
    end

    private

    attr_reader :configuration

    def host
      @host ||= configuration.public_host
    end
  end
end
