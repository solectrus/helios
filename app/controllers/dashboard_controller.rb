class DashboardController < ApplicationController
  def show
    redirect_to new_setup_path unless Configuration.current.setup_completed?

    @compose_services = Compose.load.services.sorted
    @containers_by_service = DockerHost::Container.all.index_by(&:service_name)
    @host = request.host
    @stopped_services = stopped_service_names
    @any_running = @stopped_services.size < @compose_services.size
  end

  private

  def stopped_service_names
    @compose_services.reject { |service| @containers_by_service[service.name]&.running? }.map(&:name)
  end
end
