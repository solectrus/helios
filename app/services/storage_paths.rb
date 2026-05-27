class StoragePaths
  # Docker named-volume name: starts with alphanumeric, no slashes — mirrors
  # Import::ConfigurationImporter::VolumeResolver::NAMED_VOLUME_RE.
  NAMED_VOLUME_RE = /\A[a-zA-Z0-9][a-zA-Z0-9_.-]*\z/

  def self.call(configuration: Configuration.current)
    new(configuration).call
  end

  def initialize(configuration)
    @configuration = configuration
  end

  # Returns a hash keyed by config setting (`'postgresql'`, `'reverse_proxy'`,
  # …) with the effective host path for each persistent service. Order and
  # selection come from Export::Compose.persistent_services so a new
  # volume-bearing service shows up here automatically. Docker named volumes
  # are returned as a localized "Docker volume: <name>" label so the UI never
  # claims a bind-mount path for them.
  def call
    Export::Compose.persistent_services.to_h do |service_class|
      [service_class.config_keys.first, path_for(service_class)]
    end
  end

  private

  attr_reader :configuration

  def path_for(service_class)
    setting = service_class.config_keys.first
    configured = configuration.public_send(setting).volume_path.presence
    return default_path(service_class.service_name) unless configured
    return I18n.t('storage_paths.docker_volume', name: configured) if named_volume?(configured)
    return configured if Pathname.new(configured).absolute?

    File.expand_path(configured, host_data_path)
  end

  def default_path(service_name)
    File.join(host_data_path, service_name)
  end

  def named_volume?(value)
    !value.start_with?('/') && value.match?(NAMED_VOLUME_RE)
  end

  def host_data_path
    @host_data_path ||= Orchestration::Runner.host_data_path
  end
end
