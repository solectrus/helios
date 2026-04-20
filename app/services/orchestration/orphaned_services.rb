module Orchestration
  class OrphanedServices
    # Managed service names that HELIOS knows about.
    # Reuse the canonical list from the import detector.
    MANAGED_SERVICES =
      Import::ConfigurationImporter::UnmanagedDetector::MANAGED_SERVICES

    # Returns containers that are running (or stoppable) for managed services
    # which are no longer defined in the current compose.yaml.
    # Accepts pre-loaded data to avoid redundant I/O when the caller
    # already has compose services and containers available.
    def self.detect(compose_services: nil, containers: nil)
      compose_service_names =
        (compose_services || ::Compose.load.services).to_set(&:name)

      (containers || Orchestration::Container.all)
        .select { |c| orphaned?(c, compose_service_names) }
    end

    def self.orphaned?(container, compose_service_names)
      name = container.service_name
      return false if name.blank?

      MANAGED_SERVICES.include?(name) &&
        compose_service_names.exclude?(name) &&
        container.stoppable?
    end
    private_class_method :orphaned?
  end
end
