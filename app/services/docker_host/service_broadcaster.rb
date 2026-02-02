module DockerHost
  class ServiceBroadcaster
    def initialize(listener_id: nil)
      @listener_id = listener_id
    end

    def broadcast(service_name)
      Rails.application.reloader.wrap do
        DockerHost::Container.invalidate_cache
        container = DockerHost::Container.find(service_name)
        compose_service = Compose.load.services.find(service_name)

        return false unless compose_service

        broadcast_service_row(service_name, container, compose_service)
        broadcast_service_status(service_name, container)
        true
      end
    rescue StandardError => e
      log_error(service_name, e)
      false
    end

    private

    def broadcast_service_row(service_name, container, compose_service)
      Turbo::StreamsChannel.broadcast_replace_to(
        'services',
        target: "service-#{service_name}",
        html: render_service_row(container, compose_service),
      )
    end

    def broadcast_service_status(service_name, container)
      Turbo::StreamsChannel.broadcast_replace_to(
        'services',
        target: "service-#{service_name}-status",
        html: render_service_status(service_name, container),
      )
    end

    def render_service_row(container, compose_service)
      ApplicationController.render(
        ServiceRow::Component.new(
          compose_service:,
          container:,
          host: 'localhost',
          pending: false,
        ),
        layout: false,
      )
    end

    def render_service_status(service_name, container)
      ApplicationController.render(
        ServiceStatus::Component.new(service_name:, container:),
        layout: false,
      )
    end

    def log_error(service_name, error)
      prefix = @listener_id ? "[#{@listener_id}] " : ''
      EventsListener::Logging.logger.error(
        "#{prefix}Broadcast error for #{service_name}: #{error.class}: #{error.message}",
      )
    end
  end
end
