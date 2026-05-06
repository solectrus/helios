module Services
  class TasksController < BaseController
    before_action :reject_helios, only: %i[create destroy]

    # POST /services/:service_id/task - Start
    def create
      Orchestration::StackStatus.mark_starting!
      Orchestration::PendingOperations.set(service_name, :start)
      ComposeJob.perform_later(:start, service_name)
      respond_with_pending_status(status_bar: :starting)
    end

    # PATCH /services/:service_id/task - Recreate (or self-recreate for HELIOS)
    def update
      Orchestration::StackStatus.mark_starting!

      if helios?
        ComposeJob.perform_later(:self_recreate, service_name)
        redirect_to restarting_path(boot_id: Rails.application.config.boot_id)
      else
        Orchestration::PendingOperations.set(service_name, :recreate)
        ComposeJob.perform_later(:recreate, service_name)
        respond_with_pending_status(status_bar: :starting)
      end
    end

    # DELETE /services/:service_id/task - Stop
    def destroy
      Orchestration::PendingOperations.set(service_name, :stop)
      ComposeJob.perform_later(:stop, service_name)
      respond_with_pending_status
    end
  end
end
