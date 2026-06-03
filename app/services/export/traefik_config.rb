module Export
  # Generates a Traefik dynamic-configuration (file provider) snippet for the
  # "external Traefik" reverse-proxy mode: HELIOS publishes host ports, and an
  # external Traefik on another host/stack routes to them. HELIOS knows the
  # hosts (from app_host), the target IP (bind_ip) and the published ports, but
  # not the user's certResolver/middleware names — those are emitted as CHANGE_ME
  # placeholders (which fail closed) and explained in the header comment.
  class TraefikConfig
    PLACEHOLDER = 'CHANGE_ME'.freeze

    # Routable services: published host port + the host the external Traefik
    # routes (dashboard on the bare app_host, the rest on a subdomain).
    ROUTABLE = [
      { klass: Services::Dashboard, subdomain: nil },
      { klass: Services::Influxdb, subdomain: 'influxdb' },
      { klass: Services::Ingest, subdomain: 'ingest' },
      { klass: Services::Helios, subdomain: 'helios' },
    ].freeze

    HEADER = <<~COMMENT.freeze
      # Traefik dynamic configuration (file provider) for the SOLECTRUS stack.
      #
      # The stack runs behind an EXTERNAL Traefik. Merge this into your Traefik
      # file-provider configuration and reload Traefik (if your file provider
      # has no `watch: true`, restart Traefik to apply changes).
      #
      # Replace every #{PLACEHOLDER} before use:
      #   - tls.certResolver  ->  your ACME resolver name (e.g. letsencrypt)
      #   - middlewares       ->  your middlewares (e.g. security headers, IP allow-list)
      # Also confirm the `websecure` entryPoint name matches your Traefik.
    COMMENT

    def initialize(configuration)
      @configuration = configuration
    end

    def to_s
      "#{HEADER}\n#{YAML.dump(document)}"
    end

    private

    attr_reader :configuration

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
    def routable
      @routable ||= ROUTABLE.filter_map do |entry|
        klass = entry[:klass]
        next unless klass.enabled?(configuration)

        name = klass.service_name
        host = entry[:subdomain] ? "#{entry[:subdomain]}.#{base_domain}" : base_domain
        [name, host, host_port_for(name)]
      end
    end

    def host_port_for(name)
      case name
      when 'dashboard' then configuration.dashboard.host_port.presence || 3000
      when 'influxdb' then Services::Influxdb.host_port(configuration)
      when 'ingest' then Services::Ingest::PORT
      when 'helios' then 3999 # Services::Helios publishes 3999:3000
      end
    end

    def base_domain
      configuration.system.app_host.presence || 'YOUR_DOMAIN'
    end

    def target_ip
      configuration.reverse_proxy.bind_ip.presence || 'HOST_IP'
    end
  end
end
