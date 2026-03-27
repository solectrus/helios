module Orchestration
  class ServiceBroadcaster
    def self.broadcast_row(service_name, container:, compose_service:, error_message: nil)
      html =
        ApplicationController.render(
          ServiceRow::Component.new(
            compose_service:,
            container:,
            error_message:,
            lazy: false,
          ),
          layout: false,
        )

      Turbo::StreamsChannel.broadcast_replace_to(
        'services',
        target: "service-#{service_name}",
        html:,
      )
    end

    def initialize(listener_id: nil)
      @listener_id = listener_id
    end

    def broadcast(service_name)
      # Docker API calls outside executor.wrap — holding the interlock
      # shared lock during slow API calls would block the Rails reloader.
      Orchestration::Container.invalidate_cache
      Orchestration::AffectedServices.invalidate_cache
      container = Orchestration::Container.find(service_name)
      compose_service = ::Compose.load.services.find(service_name)

      return false unless compose_service

      # Only rendering + broadcasting need executor (auto-loading, DB connections)
      Rails.application.executor.wrap do
        broadcast_and_update(service_name, container, compose_service)
      end
      true
    rescue StandardError => e
      log_error(service_name, e)
      false
    end

    private

    def broadcast_and_update(service_name, container, compose_service)
      error_message = resolve_error(service_name, container)
      I18n.with_locale(EventsListener.locale) do
        self.class.broadcast_row(
          service_name,
          container:,
          compose_service:,
          error_message:,
        )
      end
      update_stack_status(service_name, container)
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

    def log_error(service_name, error)
      prefix = @listener_id ? "[#{@listener_id}] " : ''
      Orchestration::EventsListener::Logging.logger.error(
        "#{prefix}Broadcast error for #{service_name}: #{error.class}: #{error.message}",
      )
    end
  end
end
