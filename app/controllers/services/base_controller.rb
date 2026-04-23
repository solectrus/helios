module Services
  class BaseController < ApplicationController
    include TurboFrameOnly

    # Prevent browsers from landing on a turbo-frame-only URL after a reload
    # (e.g. after a server restart when Turbo requeues the pending frame request).
    before_action :require_turbo_frame

    private

    def require_turbo_frame
      redirect_unless_turbo_frame(services_path)
    end

    def service_name
      params[:service_id]
    end

    def container
      @container ||= Orchestration::Container.find(service_name)
    end

    def compose_service
      @compose_service ||= Compose.load.services.find(service_name)
    end

    def helios?
      compose_service&.helios?
    end
  end
end
