module Services
  class TasksController < BaseController
    before_action :reject_helios, only: %i[create destroy]

    # POST /services/:service_id/task - Start
    def create
      Orchestration::StackStatus.mark_starting!
      ComposeJob.perform_later(:start, service_name)
      respond_with_pending_status(status_bar: :starting)
    end

    # PATCH /services/:service_id/task - Recreate (or self-recreate for Helios)
    def update
      Orchestration::StackStatus.mark_starting!
      action = helios? ? :self_recreate : :recreate
      ComposeJob.perform_later(action, service_name)
      respond_with_pending_status(status_bar: :starting)
    end

    # DELETE /services/:service_id/task - Stop
    def destroy
      ComposeJob.perform_later(:stop, service_name)
      respond_with_pending_status
    end

    private

    def reject_helios
      head :forbidden if helios?
    end

    def respond_with_pending_status(status_bar: nil)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream_updates(status_bar:)
        end
        format.html { redirect_to services_path }
      end
    end

    def turbo_stream_updates(status_bar: nil)
      updates = [
        turbo_stream.replace("service-#{service_name}", service_row_component),
      ]
      if status_bar
        updates << turbo_stream.replace(
          'status-bar',
          StatusBar::Component.new(status: status_bar),
        )
      end
      updates
    end

    def service_row_component
      ServiceRow::Component.new(
        compose_service:,
        container:,
        pending: true,
        lazy: false,
      )
    end
  end
end
