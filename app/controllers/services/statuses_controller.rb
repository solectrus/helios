module Services
  class StatusesController < BaseController
    def show
      render ServiceStatus::Component.new(
        service_name:,
        container:,
      )
    end
  end
end
