module Services
  class BatchesController < ApplicationController
    # POST /services/batch - Start all services
    def create
      ComposeJob.perform_later(:up)
      respond_with_pending_status { |container| !container&.running? }
    end

    # DELETE /services/batch - Stop all services
    def destroy
      ComposeJob.perform_later(:down)
      respond_with_pending_status { |container| container&.running? }
    end

    private

    def respond_with_pending_status(&)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream_updates(&)
        end
        format.html { redirect_to services_path }
      end
    end

    def turbo_stream_updates
      services_to_update.map do |compose_service|
        container = containers_by_service[compose_service.name]
        turbo_stream.replace(
          "service-#{compose_service.name}",
          ServiceRow::Component.new(
            compose_service:,
            container:,
            pending: yield(container),
            lazy: false,
          ),
        )
      end
    end

    def services_to_update
      @services_to_update ||= Compose.load.services.reject(&:helios?)
    end

    def containers_by_service
      @containers_by_service ||= Orchestration::Container.all.index_by(&:service_name)
    end
  end
end
