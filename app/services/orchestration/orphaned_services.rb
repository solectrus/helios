module Orchestration
  class OrphanedServices
    # Canonical service names HELIOS generates in compose.yaml. The import
    # layer owns this list (mapped to image prefixes); we only care about the
    # names a running container might carry.
    MANAGED_SERVICES = Import::StackReader::SERVICE_IMAGE_PREFIXES.keys.freeze

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
      return false if compose_service_names.include?(name)
      return false unless container.stoppable?

      managed?(container, name)
    end
    private_class_method :orphaned?

    # A running container is HELIOS's to clean up when its service name is one we
    # generate — or, crucially for consolidated multi-device collectors, when its
    # image is a HELIOS-managed image. Importing a stack that ran one collector
    # per device (shelly-collector-fridge, shelly-collector-dishwasher, ...)
    # emits a single shelly-collector. The old per-device containers keep running
    # under their original names, which match no canonical name; the image is
    # what still identifies them as ours to stop.
    def self.managed?(container, name)
      MANAGED_SERVICES.include?(name) ||
        Import::StackReader.managed_image?(container.image)
    end
    private_class_method :managed?
  end
end
