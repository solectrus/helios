module Import
  # Import-time compatibility gate: decides whether HELIOS can adopt a given
  # stack before any import happens.
  #
  # HELIOS regenerates compose.yaml in full, so it can only accept a stack it
  # can faithfully reproduce. Today the sole criterion is the set of services —
  # every service must be reproducible, either as a managed service (typed
  # exporter) or verbatim under `_unmanaged.services`. A service whose image
  # HELIOS doesn't recognize would silently vanish on the next export, so the
  # whole import is refused, with an actionable error naming the offenders.
  # Further compatibility criteria can be added here later.
  class CompatibilityCheck
    # SOLECTRUS-universe images HELIOS round-trips today. Beyond the
    # fully-modeled services (StackReader::ALL_IMAGE_PREFIXES) this adds
    # senec-charger and tibber-collector: both currently survive verbatim as
    # `_unmanaged.services` and are slated for first-class support (Phase 2),
    # at which point their prefixes move into StackReader::SERVICE_IMAGE_PREFIXES.
    SOLECTRUS_IMAGE_PREFIXES = (
      StackReader::ALL_IMAGE_PREFIXES + %w[
        ghcr.io/solectrus/senec-charger
        ghcr.io/solectrus/tibber-collector
      ]
    ).freeze

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

    # Raise UnsupportedServicesError unless the stack is compatible.
    def call!
      offending = unsupported_services
      raise UnsupportedServicesError, offending if offending.any?
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
