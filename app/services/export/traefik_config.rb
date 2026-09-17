module Export
  # Generates a Traefik dynamic-configuration (file provider) snippet for the
  # "external Traefik" reverse-proxy mode: HELIOS publishes host ports, and an
  # external Traefik on another host/stack routes to them. HELIOS knows the
  # hosts (from app_host), the target IP (bind_ip) and the published ports, but
  # not the user's certResolver/middleware names — those are emitted as CHANGE_ME
  # placeholders (which fail closed) and explained in the header comment.
  #
  # app_host and bind_ip carry a placeholder of their own when the configuration
  # leaves them empty, which it may: neither is required, and app_host stays
  # empty wherever HELIOS is only ever reached at a loopback address. The
  # header explains those two the same way, so the reader is not left with a
  # word in a host rule that looks like a domain.
  class TraefikConfig
    PLACEHOLDER = 'CHANGE_ME'.freeze
    DOMAIN_PLACEHOLDER = 'YOUR_DOMAIN'.freeze
    IP_PLACEHOLDER = 'HOST_IP'.freeze

    INTRO = <<~COMMENT.freeze
      # Traefik dynamic configuration (file provider) for the SOLECTRUS stack.
      #
      # The stack runs behind an external Traefik. Merge this file into the
      # file-provider configuration of that Traefik, then reload Traefik. If the
      # file provider has no `watch: true`, restart Traefik instead.
    COMMENT

    OUTRO = "# Make sure that the `websecure` entryPoint name matches your Traefik.\n".freeze

    # What each placeholder stands for. Only the ones the file actually carries
    # are explained: a value the configuration fills in leaves no placeholder
    # behind, and a note about it would send the reader looking for a word that
    # is not there.
    PLACEHOLDER_NOTES = {
      PLACEHOLDER => [
        'The name of your ACME resolver and the names of your middlewares.',
        'For example letsencrypt, and a middleware for security headers.',
      ],
      DOMAIN_PLACEHOLDER => [
        'The domain that leads to this machine. HELIOS writes it here as',
        'soon as its network settings carry an address.',
      ],
      IP_PLACEHOLDER => [
        'The address that Traefik connects to. HELIOS writes it here as',
        'soon as its reverse-proxy settings carry one.',
      ],
    }.freeze

    def initialize(configuration)
      @configuration = configuration
    end

    def to_s
      body = YAML.dump(document)
      "#{INTRO}#{placeholder_section(body)}#{OUTRO}\n#{body}"
    end

    private

    attr_reader :configuration

    # The placeholder list, or nothing at all when the configuration left no
    # placeholder in the file.
    def placeholder_section(body)
      present = PLACEHOLDER_NOTES.keys.select { |placeholder| body.include?(placeholder) }
      return '' if present.empty?

      width = present.map(&:length).max + 2
      lines = present.flat_map do |placeholder|
        PLACEHOLDER_NOTES[placeholder].each_with_index.map do |note, index|
          "#   #{(index.zero? ? placeholder : '').ljust(width)}#{note}"
        end
      end

      "#\n# Replace every placeholder before you use the file:\n#{lines.join("\n")}\n#\n"
    end

    def document
      { 'http' => { 'routers' => routers, 'services' => services } }
    end

    def routers
      routable.to_h do |name, host, _port|
        ["solectrus-#{name}", {
          'rule' => "Host(`#{host}`)",
          'entryPoints' => ['websecure'],
          'middlewares' => [PLACEHOLDER],
          'service' => "solectrus-#{name}",
          'tls' => { 'certResolver' => PLACEHOLDER },
        }]
      end
    end

    def services
      routable.to_h do |name, _host, port|
        ["solectrus-#{name}", {
          'loadBalancer' => { 'servers' => [{ 'url' => "http://#{target_ip}:#{port}" }] },
        }]
      end
    end

    # [name, host, host_port] for every routable service active in this config.
    #
    # A service reaches the external Traefik through its published host port, so
    # one that publishes none is left out: its router would name a host and send
    # every request to a port that refuses the connection. InfluxDB is the only
    # one that can withhold the port here, because this mode runs no Traefik of
    # its own and the other three publish in every configuration.
    def routable
      @routable ||= Compose.externally_routable(configuration).map do |klass|
        subdomain = klass.proxy_subdomain
        host = subdomain ? "#{subdomain}.#{base_domain}" : base_domain
        [klass.service_name, host, host_port_for(klass.service_name)]
      end
    end

    def host_port_for(name)
      case name
      when 'dashboard' then Services::Dashboard.host_port(configuration)
      when 'influxdb' then Services::Influxdb.host_port(configuration)
      when 'ingest' then Services::Ingest::PORT
      when 'helios' then 3999 # Services::Helios publishes 3999:3000
      end
    end

    def base_domain
      configuration.public_host || DOMAIN_PLACEHOLDER
    end

    def target_ip
      configuration.reverse_proxy.bind_ip.presence || IP_PLACEHOLDER
    end
  end
end
