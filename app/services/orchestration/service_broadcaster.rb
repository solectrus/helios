module Orchestration
  class ServiceBroadcaster
    include Loggable

    def self.broadcast_row(service_name, container:, compose_service:, error_message: nil)
      component = ServiceRow::Component.new(
        compose_service:, container:, error_message:, lazy: false,
      )

      Turbo::StreamsChannel.broadcast_replace_to(
        'services',
        target: "service-#{service_name}",
        attributes: { method: :morph },
        html: ApplicationController.render(component, layout: false),
      )
    end

    def initialize(listener_id: nil)
      @listener_id = listener_id
    end

    def broadcast(service_name, created: false)
      # Docker API calls outside executor.wrap — holding the interlock
      # shared lock during slow API calls would block the Rails reloader.
      Orchestration::Container.invalidate_cache
      refresh_config_hashes(service_name, created:)
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
      I18n.with_locale(Orchestration::EventsListener.locale) do
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

    # A `create` event means Docker Compose recreated the container with the
    # current compose.yaml config, so the deployed hash for this service can
    # be updated. Other events (start/stop/die) don't change config hashes,
    # so no invalidation is needed.
    def refresh_config_hashes(service_name, created:)
      return unless created

      Orchestration::AffectedServices.update_deployed_hash!(service_name)
    end

    def log_error(service_name, error)
      prefix = @listener_id ? "[#{@listener_id}] " : ''
      logger.error(
        "#{prefix}Broadcast error for #{service_name}: #{error.class}: #{error.message}",
      )
    end
  end
end
