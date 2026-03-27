class ServicesController < ApplicationController
  def index
    return redirect_to configuration_path unless Configuration.current.setup_completed?

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
