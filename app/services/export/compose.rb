module Export
  class Compose
    WATCHTOWER_LABEL = 'com.centurylinklabs.watchtower.scope=solectrus'.freeze

    # Keep in sync with Compose::ServiceCollection::PRIORITY_ORDER (UI order).
    SERVICE_ORDER = [
      Services::Dashboard,
      Services::Influxdb,
      Services::Ingest,
      Services::Postgresql,
      Services::Redis,
      Services::SenecCollector,
      Services::ShellyCollector,
      Services::MqttCollector,
      Services::ForecastCollector,
      Services::PowerSplitter,
      Services::Traefik,
      Services::Watchtower,
      Services::Helios,
    ].freeze

    def self.find_service(name)
      SERVICE_ORDER.find { |klass| klass.service_name == name.to_s }
    end

    def initialize(configuration)
      @configuration = configuration
    end

    def to_yaml
      compose = ::Compose::File.new(::Compose.path)
      compose.header_comment = compose_header_comment
      compose.name = 'solectrus'

      # Unmanaged collectors are the stack's primary services in collectors_only
      # mode — render them before HELIOS's own infrastructure (watchtower, helios).
      if configuration.collectors_only?
        add_unmanaged_services(compose)
        add_class_based_services(compose)
      else
        add_class_based_services(compose)
        add_unmanaged_services(compose)
      end

      add_default_network(compose)
      add_unmanaged_volumes(compose)

      compose.to_yaml
    end

    def data_directories
      active_service_classes.flat_map { |klass| klass.new(configuration).data_directories }.uniq
    end

    private

    attr_reader :configuration

    def add_class_based_services(compose)
      active_service_classes.each do |service_class|
        compose.add_service(
          service_class.service_name,
          build_service_hash(service_class),
          comment: service_class.comment,
        )
      end
    end

    def build_service_hash(service_class)
      service_hash = service_class.new(configuration).to_h.compact.reverse_merge(default_logging)
      service_hash[:image] = ::Compose.normalize_image(service_hash[:image])
      ServiceOverrides.apply(configuration, service_class.service_name, service_hash)
      service_hash[:labels] = (Array(service_hash[:labels]) + [WATCHTOWER_LABEL]).uniq
      sort_environment!(service_hash)
      service_hash
    end

    # TZ stays first (Docker convention); the rest is alphabetized so each
    # service's compose entry has a predictable, diff-stable layout. Numeric
    # runs are compared as integers so MAPPING_2 sorts before MAPPING_10.
    def sort_environment!(service_hash)
      env = service_hash[:environment]
      return unless env.is_a?(Array)

      service_hash[:environment] = env.sort_by do |entry|
        name = entry.to_s.split('=', 2).first
        [name == 'TZ' ? 0 : 1, natural_sort_key(name)]
      end
    end

    def natural_sort_key(string)
      string.split(/(\d+)/).each_with_index.map { |part, i| i.odd? ? part.to_i : part }
    end

    def active_service_classes
      @active_service_classes ||= SERVICE_ORDER.select do |service_class|
        service_class.enabled?(configuration)
      end
    end

    def add_unmanaged_services(compose)
      unmanaged = configuration.unmanaged
      return if unmanaged.services.blank?

      unmanaged.services.each do |name, config|
        next if config.blank?

        # env_values is HELIOS-internal state (values for the environment list,
        # rendered into .env on export) — not a compose key.
        service_config = config.to_h.except('env_values')
        compose.add_service(name, service_config,
                            comment: 'Unmanaged service (preserved from existing installation)')
      end
    end

    def default_logging
      { logging: { driver: 'json-file', options: { 'max-size' => '10m', 'max-file' => '3' } } }
    end

    # Pin the bridge network to a stable name so it stays the same if the
    # compose project is ever renamed (which would otherwise change Compose's
    # auto-name `<project>_default`). Unmanaged services only reference the
    # compose-internal `default` alias, so the actual Docker network name is
    # transparent to them.
    def add_default_network(compose)
      compose.networks['default'] = { 'name' => network_name }
    end

    def network_name
      configuration.system['network_name'].presence || ConfigSchema::DEFAULT_NETWORK_NAME
    end

    # Top-level `volumes:` declarations carried over from the source compose
    # (named volumes referenced by managed or unmanaged services). Without
    # the declaration, Compose would create implicit anonymous volumes
    # rather than reusing the existing ones.
    def add_unmanaged_volumes(compose)
      volumes = configuration.unmanaged.volumes
      return if volumes.blank?

      volumes.each { |name, config| compose.volumes[name] = config.to_h }
    end

    def compose_header_comment
      Env::WARNING_BANNER
    end
  end
end
