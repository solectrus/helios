class DashboardController < ApplicationController
  def show
    redirect_to new_setup_path unless Configuration.current.setup_completed?

    @compose_services = Compose.load.services.sorted
  end
end
