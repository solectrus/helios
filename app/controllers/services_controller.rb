class ServicesController < ApplicationController
  before_action :set_service_name
  before_action :reject_helios_commands

  def start
    ComposeJob.perform_later(:start, @service_name)
    respond_with_pending_status
  end

  def stop
    ComposeJob.perform_later(:stop, @service_name)
    respond_with_pending_status
  end

  def restart
    ComposeJob.perform_later(:restart, @service_name)
    respond_with_pending_status
  end

  private

  def set_service_name
    @service_name = params[:id]
  end

  def reject_helios_commands
    return unless @service_name == 'helios'

    head :forbidden
  end

  def respond_with_pending_status
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "service-#{@service_name}",
          service_row_component,
        )
      end
      format.html { redirect_to root_path }
    end
  end

  def service_row_component
    container = DockerHost::Container.find(@service_name)
    compose_service = Compose.load.services.find(@service_name)

    ServiceRow::Component.new(
      compose_service:,
      container:,
      host: request.host,
      pending: true,
    )
  end
end
