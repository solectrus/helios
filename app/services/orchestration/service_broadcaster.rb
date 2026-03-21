module Orchestration
  class ServiceBroadcaster
    def initialize(listener_id: nil)
      @listener_id = listener_id
    end

    def broadcast(service_name)
      Rails.application.reloader.wrap do
        Orchestration::Container.invalidate_cache
        container = Orchestration::Container.find(service_name)
        compose_service = ::Compose.load.services.find(service_name)

        return false unless compose_service

        broadcast_service_row(service_name, container, compose_service)
        update_stack_status(service_name, container)
        true
      end
    rescue StandardError => e
      log_error(service_name, e)
      false
    end

    private

    def broadcast_service_row(service_name, container, compose_service)
      error_message = resolve_error(service_name, container)

      Turbo::StreamsChannel.broadcast_replace_to(
        'services',
        target: "service-#{service_name}",
        html: render_service_row(container, compose_service, error_message:),
      )
    end

    def update_stack_status(service_name, container)
      status = container&.effective_status || :stopped
      Orchestration::StackStatus.update(service_name, status)
    end

    def resolve_error(service_name, container)
      if container&.running?
        Orchestration::ErrorStore.clear(service_name)
        nil
      else
        Orchestration::ErrorStore.get(service_name)
      end
    end

    def render_service_row(container, compose_service, error_message: nil)
      ApplicationController.render(
        ServiceRow::Component.new(
          compose_service:,
          container:,
          error_message:,
          lazy: false,
        ),
        layout: false,
      )
    end

    def log_error(service_name, error)
      prefix = @listener_id ? "[#{@listener_id}] " : ''
      Orchestration::EventsListener::Logging.logger.error(
        "#{prefix}Broadcast error for #{service_name}: #{error.class}: #{error.message}",
      )
    end
  end
end
