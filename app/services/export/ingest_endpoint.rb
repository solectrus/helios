module Export
  # Address an external source has to write to while Ingest runs. Ingest speaks
  # the InfluxDB write API, so such a source only has to swap the address; token
  # and bucket stay the same. A source that keeps writing to InfluxDB is missing
  # from the house_power recalculation, and Ingest then writes no house_power at
  # all (see Configuration#ingest_required?).
  #
  # Ingest always publishes its host port, and managed Traefik does not route it
  # (TraefikConfig::ROUTABLE covers the external-proxy mode only), so the host
  # port is the address in every mode but that one.
  #
  # Returns nil when nothing in the configuration names the machine: app_host is
  # required in its own form but in no completeness check, and an imported stack
  # without APP_HOST keeps it empty. A caller then names the port alone instead
  # of showing an address with a placeholder in it.
  class IngestEndpoint
    PORT = Services::Ingest::PORT

    def self.url(configuration = Configuration.current)
      new(configuration).url
    end

    def initialize(configuration)
      @configuration = configuration
    end

    def url
      return "https://ingest.#{host}" if configuration.reverse_proxy_external? && host

      "http://#{host}:#{PORT}" if host
    end

    private

    attr_reader :configuration

    def host
      @host ||= configuration.system.app_host.presence ||
                configuration.reverse_proxy.app_domain.presence
    end
  end
end
