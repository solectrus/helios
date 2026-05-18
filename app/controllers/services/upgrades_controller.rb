module Services
  class UpgradesController < BaseController
    before_action :require_postgresql_upgrade

    # POST /services/:service_id/upgrade - PostgreSQL major-version upgrade
    def create
      Orchestration::StackStatus.mark_starting!
      Orchestration::PendingOperations.set(service_name, :upgrade)
      PostgresqlUpgradeJob.perform_later
      respond_with_pending_status(status_bar: :starting)
    end

    private

    # The major-version upgrade is PostgreSQL-specific and only valid while an
    # older major is actually running on the managed data directory.
    def require_postgresql_upgrade
      return if service_name == 'postgresql' &&
                Orchestration::PostgresqlUpgrade.available?(container)

      head :not_found
    end
  end
end
