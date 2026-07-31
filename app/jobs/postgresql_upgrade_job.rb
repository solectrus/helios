class PostgresqlUpgradeJob < ApplicationJob
  queue_as :default

  SERVICE = Orchestration::PostgresqlUpgrade::SERVICE

  # Resumes an upgrade that a killed HELIOS left half-finished. Called once per
  # boot from config/puma.rb, so it never fires under rake, console or RSpec.
  # The pending operation is set right here, synchronously during boot: it
  # keeps the first /services render from offering an upgrade button (or a
  # start button) for a database the recovery is about to take over.
  def self.recover_later
    return unless Orchestration::PostgresqlUpgrade.interrupted?

    Orchestration::PendingOperations.set(SERVICE, :upgrade)
    perform_later(recover: true)
  rescue StandardError => e
    # Runs inside Puma's boot hook: whatever goes wrong here, HELIOS still has
    # to come up — it is the only way to reach the stack at all.
    Rails.logger.error("PostgresqlUpgradeJob.recover_later failed: #{e.class}: #{e.message}")
  end

  # An automatic update recreating PostgreSQL between the dump and the restore
  # would destroy the cluster the upgrade is rebuilding, so the whole run holds
  # an update pause. Unlike the detached runners, this operation finishes
  # inside the HELIOS process, so it can end the pause itself.
  def perform(recover: false)
    Orchestration::UpdatePause.pause!(:postgresql_upgrade)
    Orchestration::ErrorStore.clear(SERVICE)
    recover ? Orchestration::PostgresqlUpgrade.recover! : Orchestration::PostgresqlUpgrade.call
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
