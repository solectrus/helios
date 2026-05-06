module Services
  class BatchesController < ApplicationController
    # POST /services/batch - Start all services (also recreates containers
    # whose config has changed, since `docker compose up` is idempotent).
    def create
      Orchestration::StackStatus.mark_starting!
      ComposeJob.perform_later(:up)

      respond_with_pending_status(:starting, action: :up) do |_, container|
        !container&.running?
      end
    end

    # DELETE /services/batch - Stop all services
    def destroy
      Orchestration::StackStatus.mark_stopping!
      ComposeJob.perform_later(:down)
      respond_with_pending_status(:stopping, action: :down) do |_, container|
        container&.running?
      end
    end

    private

    def respond_with_pending_status(status, action:, &)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream_updates(status, action, &)
        end
        format.html { redirect_to services_path }
      end
    end

    def turbo_stream_updates(status, action, &)
      service_row_updates(action, &) + [status_bar_update(status)]
    end

    def service_row_updates(action, &)
      services_to_update.map do |compose_service|
        service_row_update(compose_service, action, &)
      end
    end

    def service_row_update(compose_service, action)
      container = containers_by_service[compose_service.name]
      pending = yield(compose_service, container)
      if pending
        Orchestration::PendingOperations.set(compose_service.name, action)
      end
      turbo_stream.replace(
        "service-#{compose_service.name}",
        ServiceRow::Component.new(
          compose_service:, container:, pending:, lazy: false,
        ),
      )
    end

    def status_bar_update(status)
      turbo_stream.replace('status-bar', StatusBar::Component.new(status:))
    end

    def services_to_update
      @services_to_update ||= Compose.load.services.reject(&:helios?)
    end

    def containers_by_service
      @containers_by_service ||=
        Orchestration::Container.all.index_by(&:service_name)
    end
  end
end
