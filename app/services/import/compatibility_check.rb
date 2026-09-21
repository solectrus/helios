module Import
  # Import-time compatibility gate: decides whether HELIOS can adopt a given
  # stack before any import happens.
  #
  # HELIOS regenerates compose.yaml in full, so it can only accept a stack it
  # can faithfully reproduce. Two criteria:
  #
  # * Every service must be reproducible, either as a managed service (typed
  #   exporter) or verbatim under `_unmanaged.services`. A service whose image
  #   HELIOS doesn't recognize would silently vanish on the next export.
  # * Every Docker network a service joins must be one HELIOS writes again:
  #   the stack's own `default`, and the one external network an outside proxy
  #   reaches the stack over (see
  #   ConfigurationImporter::ReverseProxyExtractor#shared_network). A second
  #   network would be dropped, and the services on it would lose the way they
  #   are reached today without anything saying so.
  # * Every Traefik label on a managed service must be one HELIOS writes
  #   again. HELIOS owns the routers of its own services, so a label that says
  #   something else (a middleware it does not know, a router at another
  #   address) would be replaced by its own on the next export.
  #
  # Either way the whole import is refused, with an actionable error naming
  # what stands in the way.
  class CompatibilityCheck
    # SOLECTRUS-universe images HELIOS round-trips today. All fully-modeled
    # services live in StackReader::ALL_IMAGE_PREFIXES — including
    # tibber-collector (Phase 2a) and senec-charger (Phase 2b), both promoted to
    # first-class managed services that match via their StackReader prefixes and
    # are never treated as `_unmanaged`.
    SOLECTRUS_IMAGE_PREFIXES = StackReader::ALL_IMAGE_PREFIXES

    # Curated third-party companion images HELIOS tolerates but never
    # configures. dozzle was recommended in earlier SOLECTRUS hosting guides,
    # so many installations include it; it round-trips verbatim under
    # `_unmanaged.services`.
    COMPANION_IMAGE_PREFIXES = %w[amir20/dozzle].freeze

    ALLOWED_IMAGE_PREFIXES = (SOLECTRUS_IMAGE_PREFIXES + COMPANION_IMAGE_PREFIXES).freeze

    # Traefik labels HELIOS writes again for a service of its own. The router
    # name is the user's in the wild ("app-solectrus", "influx-api"), so the
    # shape is matched rather than the name.
    #
    # The redirect middleware is in here although HELIOS writes no middleware:
    # it is how the older SOLECTRUS setup sent port 80 to HTTPS, and HELIOS
    # does the same on the `web` entrypoint (see Export::Services::Traefik).
    #
    # The network label belongs to a stack an outside proxy routes over a
    # shared network. HELIOS writes it for every service it routes there (see
    # Export::Services::Base#network_label), so a stack that carries it already
    # is one it can write again.
    REPRODUCIBLE_LABELS = [
      /\Atraefik\.enable=/i,
      /\Atraefik\.docker\.network=/i,
      /\Atraefik\.http\.routers\.[^.]+\.(rule|entrypoints|service|middlewares|tls|tls\.certresolver)=/i,
      /\Atraefik\.http\.services\.[^.]+\.loadbalancer\.server\.port=/i,
      /\Atraefik\.http\.middlewares\.[^.]+\.redirectscheme\./i,
    ].freeze

    ROUTER_RULE = /\Atraefik\.http\.routers\.([^.]+)\.rule=(.*)\z/i
    ROUTER_MIDDLEWARES = /\Atraefik\.http\.routers\.([^.]+)\.middlewares=(.*)\z/i
    REDIRECT_MIDDLEWARE = /\Atraefik\.http\.middlewares\.([^.]+)\.redirectscheme\./i
    HOST_RULE = /\AHost\(`([^`]+)`\)\z/i

    def initialize(reader)
      @reader = reader
    end

    # Offending services as [{ 'service' => name, 'image' => image }, ...];
    # empty when every service is recognized.
    def unsupported_services
      service_images
        .reject { |_name, image| supported?(image) }
        .map { |name, image| { 'service' => name, 'image' => image } }
    end

    # Networks a service joins that the export would not write again. The
    # compose default is always written, and so is the single external network
    # the importer captures for an outside proxy; anything beyond that is left
    # over.
    def unsupported_networks
      raw = @reader.raw_compose
      reproduced = ['default'] + ConfigurationImporter::ReverseProxyExtractor.foreign_networks(raw).first(1)

      (raw['services'] || {}).values
                             .flat_map { |service| ConfigurationImporter::ReverseProxyExtractor.network_names(service) }
                             .uniq - reproduced
    end

    # Traefik labels on managed services that the export would not write
    # again, as [{ 'service' => name, 'label' => label }, ...]. Two shapes
    # count: a label outside REPRODUCIBLE_LABELS, and a router that answers at
    # another address than the one HELIOS routes the stack at.
    def unsupported_routing
      managed_labels.flat_map do |name, labels|
        unknown = labels.reject { |label| reproducible?(label) }

        (unknown + foreign_rules(labels)).uniq.map { |label| { 'service' => name, 'label' => label } }
      end
    end

    # Raise UnsupportedStackError unless the stack is compatible.
    def call!
      services = unsupported_services
      networks = unsupported_networks
      routing = unsupported_routing
      return if services.empty? && networks.empty? && routing.empty?

      raise UnsupportedStackError.new(services, networks, routing)
    end

    private

    # Each service as the user authored it, paired with its resolved image
    # so `${VAR}`-based image references are expanded before matching.
    def service_images
      (@reader.raw_compose['services'] || {}).keys.index_with do |name|
        @reader.service(name)&.fetch('image', nil)
      end
    end

    def supported?(image)
      image.present? && StackReader.image_matches?(image, ALLOWED_IMAGE_PREFIXES)
    end

    # Traefik labels per managed service, read from the resolved view so a
    # rule spelled `Host(${APP_DOMAIN})` arrives with the domain in it.
    def managed_labels
      @managed_labels ||= StackReader::SERVICE_IMAGE_PREFIXES.keys.index_with { |name| traefik_labels_of(name) }
                                                             .reject { |_name, labels| labels.empty? }
    end

    def traefik_labels_of(name)
      labels = @reader.service(name)&.dig('labels')
      case labels
      when Array then labels.map(&:to_s).select { |label| label.start_with?('traefik.') }
      when Hash then labels.filter_map { |key, value| "#{key}=#{value}" if key.to_s.start_with?('traefik.') }
      else []
      end
    end

    def reproducible?(label)
      REPRODUCIBLE_LABELS.any? { |pattern| label.match?(pattern) }
    end

    # Rules of routers that answer somewhere else than HELIOS routes the
    # stack. A router that only sends a request on to HTTPS is left out: its
    # rule matches every host on purpose, and HELIOS does the same on the
    # `web` entrypoint.
    def foreign_rules(labels)
      redirecting = redirect_routers(labels)

      labels.select do |label|
        router, rule = label.match(ROUTER_RULE)&.captures
        router && redirecting.exclude?(router) && rule[HOST_RULE, 1] != routed_host
      end
    end

    def redirect_routers(labels)
      labels.filter_map do |label|
        router, names = label.match(ROUTER_MIDDLEWARES)&.captures
        router if router && middleware_names(names).all? { |name| redirect_middlewares.include?(name) }
      end
    end

    def middleware_names(value)
      value.split(',').map { |name| name.strip.sub(/@\w+\z/, '') }
    end

    # Names of the redirect middlewares the whole stack defines, because a
    # router may name one that another service declares.
    def redirect_middlewares
      @redirect_middlewares ||= managed_labels.values.flatten.filter_map { |l| l[REDIRECT_MIDDLEWARE, 1] }
    end

    # The address the stack answers at, taken from the dashboard router,
    # which is the one HELIOS rebuilds every other router against.
    def routed_host
      @routed_host ||= traefik_labels_of('dashboard').filter_map { |label| label.match(ROUTER_RULE)&.captures&.last }
                                                     .filter_map { |rule| rule[HOST_RULE, 1] }
                                                     .first
    end
  end
end
