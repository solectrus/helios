# Permanently removes an unmanaged service: drops its `_unmanaged.services`
# entry, regenerates compose.yaml without it, stops & removes the (now
# orphaned) container, and removes the row from the services list.
class ServiceRemovalJob < ApplicationJob
  queue_as :default

  def perform(service_name)
    return unless Configuration.current.remove_unmanaged_service(service_name)

    Export::Builder.new(Configuration.current).write!

    container = Orchestration::Container.find(service_name)
    container.stop_and_remove! if container&.stoppable?

    broadcast_removal(service_name)
  ensure
    Orchestration::PendingOperations.clear(service_name)
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
