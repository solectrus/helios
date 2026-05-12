module Services
  class OrphanedTasksController < BaseController
    # DELETE /services/:service_id/orphaned_task - Stop and remove orphaned container
    def destroy
      if container&.stoppable?
        OrphanedStopJob.perform_later(service_name)
        respond_with_pending_status
      else
        redirect_to services_path
      end
    end

    private

    def respond_with_pending_status
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream:
            turbo_stream.replace(
              "service-#{service_name}",
              OrphanedServiceRow::Component.new(
                container:,
                pending: true,
              ),
              method: :morph,
            )
        end
        format.html { redirect_to services_path }
      end
    end
  end
end
