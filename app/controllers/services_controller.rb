class ServicesController < ApplicationController
  def index
    return redirect_to configuration_path unless Configuration.current.setup_completed?

    @compose_services = Compose.load.services.sorted

    # Preload containers on Turbo Frame requests (tab switches) to avoid skeleton flicker.
    # On full page loads (initial visit, refresh) use lazy loading for faster first paint.
    if turbo_frame_request?
      @containers = Orchestration::Container.all.index_by(&:service_name)
    end
  rescue Orchestration::ConnectionError
    @containers = nil
  end
end
