module Services
  class RowsController < BaseController
    def show
      render ServiceRow::Component.new(
        compose_service:,
        container:,
        error_message: Compose::ServiceStore.get(service_name),
        pending: Compose::ServiceStore.pending?(service_name),
        lazy: false,
      )
    end
  end
end
