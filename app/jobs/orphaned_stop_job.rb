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
  end

  private

  def broadcast_removal(service_name)
    Turbo::StreamsChannel.broadcast_remove_to(
      'services',
      target: "service-#{service_name}",
    )
  end
end
