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

    def reject_helios
      head :forbidden if helios?
    end

    def respond_with_pending_status(status_bar: nil)
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream_updates(status_bar:) }
        format.html { redirect_to services_path }
      end
    end

    def turbo_stream_updates(status_bar: nil)
      updates = [
        turbo_stream.replace("service-#{service_name}", pending_service_row_component, method: :morph),
      ]
      if status_bar
        updates << turbo_stream.replace('status-bar', StatusBar::Component.new(status: status_bar), method: :morph)
      end
      updates
    end

    def pending_service_row_component
      ServiceRow::Component.new(
        compose_service:,
        container:,
        pending: true,
        lazy: false,
      )
    end
  end
end
