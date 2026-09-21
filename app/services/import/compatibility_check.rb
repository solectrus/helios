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

    # Raise UnsupportedStackError unless the stack is compatible.
    def call!
      services = unsupported_services
      networks = unsupported_networks
      raise UnsupportedStackError.new(services, networks) if services.any? || networks.any?
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
  end
end
