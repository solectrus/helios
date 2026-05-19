class ServicesController < ApplicationController
  def index
    # Before setup is completed there is no stack to manage — index.html.erb
    # renders an empty state instead of the (helios-only) service list.
    return unless (@setup_completed = Configuration.current.setup_completed?)

    Export::Builder.new(Configuration.current).write_if_stale!
    compose = Compose.load
    @compose_services = compose.services.sorted

    # Preload containers on Turbo Frame requests (tab switches) to avoid skeleton flicker.
    # On full page loads (initial visit, refresh) use lazy loading for faster first paint.
    if turbo_frame_request?
      all_containers = Orchestration::Container.all
      @containers = all_containers.index_by(&:service_name)
    end

    @orphaned_containers = Orchestration::OrphanedServices.detect(
      compose_services: compose.services,
      containers: all_containers,
    )
  rescue Orchestration::ConnectionError
    @containers = nil
    @orphaned_containers = nil
  end
end
