class OrphanedStopJob < ApplicationJob
  queue_as :default

  def perform(service_name)
    container = Orchestration::Container.find(service_name)
    return unless container&.stoppable?

    container.stop_and_remove!
    broadcast_removal(service_name)
  ensure
    Orchestration::Container.invalidate_cache
    Orchestration::StackStatus.refresh!
    # Frees the name for the automatic removal again. Last, because the removal
    # above emits stop/die/destroy events: clearing before the refresh lets one
    # of them claim the name again and queue a second job.
    Orchestration::PendingOperations.clear(service_name)
  end

  private

  def broadcast_removal(service_name)
    Turbo::StreamsChannel.broadcast_remove_to(
      'services',
      target: "service-#{service_name}",
    )
  end
end
