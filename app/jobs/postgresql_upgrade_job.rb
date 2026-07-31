class PostgresqlUpgradeJob < ApplicationJob
  queue_as :default

  SERVICE = Orchestration::PostgresqlUpgrade::SERVICE

  # An automatic update recreating PostgreSQL between the dump and the restore
  # would destroy the cluster the upgrade is rebuilding, so the whole run holds
  # an update pause. Unlike the detached runners, this operation finishes
  # inside the HELIOS process, so it can end the pause itself.
  def perform
    Orchestration::UpdatePause.pause!(:postgresql_upgrade)
    Orchestration::ErrorStore.clear(SERVICE)
    Orchestration::PostgresqlUpgrade.call
  rescue Orchestration::PostgresqlUpgrade::UpgradeError => e
    logger.error("PostgresqlUpgradeJob failed: #{e.message}")
    Orchestration::ErrorStore.set(SERVICE, e.message)
  ensure
    # Clear the pending flag before broadcasting so the row renders its real
    # status (or the stored error), not the spinner the controller put up.
    Orchestration::PendingOperations.clear(SERVICE)
    broadcast
    Orchestration::StackStatus.refresh!
    # Last: the pending flag it just cleared is what tells UpdatePause an
    # upgrade is still in flight.
    Orchestration::UpdatePause.resume_if_idle!
  end

  private

  def broadcast
    Orchestration::Container.invalidate_cache
    compose_service = Compose.load.services.find(SERVICE)
    return unless compose_service

    Orchestration::ServiceBroadcaster.broadcast_row(
      SERVICE,
      container: Orchestration::Container.find(SERVICE),
      compose_service:,
      error_message: Orchestration::ErrorStore.get(SERVICE),
    )
  rescue StandardError => e
    logger.error("PostgresqlUpgradeJob broadcast failed: #{e.class}: #{e.message}")
  end
end
