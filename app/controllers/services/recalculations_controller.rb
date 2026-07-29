module Services
  class RecalculationsController < BaseController
    before_action :require_power_splitter

    # POST /services/:service_id/recalculation - Recalculate all derived values
    def create
      if Orchestration::PowerSplitter::Recalculation.call(container)
        redirect_to services_path, notice: t('.success')
      else
        redirect_to services_path, alert: t('.failure')
      end
    end

    private

    # Recalculating is power-splitter-specific; no other service offers it.
    def require_power_splitter
      head :not_found unless service_name == Orchestration::PowerSplitter::SERVICE
    end
  end
end
