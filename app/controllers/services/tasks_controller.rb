module Services
  class TasksController < BaseController
    before_action :reject_helios

    # POST /services/:service_id/task - Start
    def create
      ComposeJob.perform_later(:start, service_name)
      respond_with_pending_status
    end

    # PATCH /services/:service_id/task - Restart
    def update
      ComposeJob.perform_later(:restart, service_name)
      respond_with_pending_status
    end

    # DELETE /services/:service_id/task - Stop
    def destroy
      ComposeJob.perform_later(:stop, service_name)
      respond_with_pending_status
    end

    private

    def reject_helios
      head :forbidden if service_name == 'helios'
    end

    def respond_with_pending_status
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "service-#{service_name}",
            service_row_component,
          )
        end
        format.html { redirect_to root_path }
      end
    end

    def service_row_component
      ServiceRow::Component.new(
        compose_service:,
        container:,
        host: request.host,
        pending: true,
      )
    end
  end
end
