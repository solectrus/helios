module Orchestration
  module VersionExtractor
    OCI_LABEL = 'org.opencontainers.image.version'.freeze
    ENV_VERSION_PATTERN = /^([A-Z][A-Z0-9_]*)_VERSION=(.+)$/
    # A real version starts with an optional "v" followed by a digit. Branch or
    # floating tags (develop, latest, main, ...) don't, so we can tell them apart.
    VERSION_LIKE = /\Av?\d/
    # Language-runtime versions baked into base images — not the app's version.
    ENV_VERSION_DENYLIST = %w[RUBY NODE PYTHON GOLANG GO].freeze

    # Load all extractors when module is loaded
    Dir[File.join(__dir__, 'version_extractor', '*.rb')].each { |f| require f }

    def self.extract(container)
      version =
        from_specific_extractor(container) ||
        from_oci_label(container) ||
        from_env(container)
      version&.delete_prefix('v')
    end

    def self.from_specific_extractor(container)
      Base.subclasses.each do |extractor_class|
        extractor = extractor_class.new(container)
        next unless extractor.match?

        version = extractor.extract
        return version if version.present?
      end

      nil
    end

    def self.from_oci_label(container)
      labels = container.json.dig('Config', 'Labels') || {}
      label = labels[OCI_LABEL].presence
      label if label&.match?(VERSION_LIKE)
    end

    def self.from_env(container)
      env = container.json.dig('Config', 'Env') || []
      env.each do |var|
        match = var.match(ENV_VERSION_PATTERN)
        next unless match
        next if ENV_VERSION_DENYLIST.include?(match[1])

        return match[2]
      end

      nil
    end

    private_class_method :from_specific_extractor, :from_oci_label, :from_env
  end
end
