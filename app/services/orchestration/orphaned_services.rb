module Orchestration
  class OrphanedServices
    extend Loggable

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

    # Removes every orphan found, rather than waiting for the user to click it
    # away. A container left behind by a service rename keeps running under its
    # old name, and `restart: always` brings it back after every host reboot.
    # When it is a database it writes to the same directory as the managed
    # service that replaced it, and the two clusters destroy each other's data.
    # This is the same cleanup `docker compose up --remove-orphans` performs on
    # a global start, only no longer tied to the user pressing something.
    #
    # Skipped until the setup is complete: before that compose.yaml does not
    # describe the stack yet, and every running container would look orphaned.
    def self.prune!(containers: nil)
      return unless Configuration.current.setup_completed?

      # The container list is cached for seconds and only the broadcast path
      # refreshes it. A leftover container that just appeared would not be in
      # it yet, which is exactly the moment this runs. A caller that has just
      # refreshed hands over its list instead, so we do not drop the inspects
      # it warmed and ask Docker for the same thing again.
      Orchestration::Container.invalidate_cache unless containers

      detect(containers:).each { |container| remove!(container.service_name) }
    end

    # Claims the name and queues its removal. Returns false when a removal for
    # it is already on its way. Both the automatic sweep and the Remove button
    # go through here, so a click during a running sweep adds no second job for
    # the same container — and OrphanedStopJob's `ensure` clears a claim that
    # exactly one of them holds.
    def self.remove!(name)
      return false unless PendingOperations.claim?(name, :remove)

      logger.warn("Removing orphaned container for #{name}")
      OrphanedStopJob.perform_later(name)
      true
    rescue StandardError
      # Nothing runs the job's `ensure` if the queue refuses the job, and a
      # claim nobody clears keeps the container out of every later sweep.
      PendingOperations.clear(name)
      raise
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
    #
    # It reads the configured image, not the one the container list reports.
    # After a rename the leftover container keeps running while the tag moves on
    # to the newly pulled image, and the list then names it by bare `sha256:`
    # digest, which matches no prefix. A legacy `db` stayed invisible that way
    # next to a managed `postgresql`, both writing to the same data directory.
    def self.managed?(container, name)
      MANAGED_SERVICES.include?(name) ||
        Import::StackReader.managed_image?(container.configured_image)
    end
    private_class_method :managed?
  end
end
