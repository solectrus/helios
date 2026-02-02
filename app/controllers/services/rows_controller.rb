module Services
  class RowsController < BaseController
    def show
      render ServiceRow::Component.new(
        compose_service:,
        container:,
        lazy: false,
      )
    end
  end
end
