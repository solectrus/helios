module Services
  class RowsController < BaseController
    def show
      render ServiceRow::Component.new(
        compose_service:,
        container:,
        error_message: Compose::ErrorStore.get(service_name),
        lazy: false,
      )
    end
  end
end
