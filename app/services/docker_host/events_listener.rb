module DockerHost
  class EventsListener
    BROADCAST_DELAY = 0.5

    class << self
      def start
        return if @thread&.alive?

        @thread = Thread.new { new.listen }
        Rails.logger.info 'DockerHost::EventsListener started'
      end

      def stop
        @thread&.kill
        @thread = nil
        Rails.logger.info 'DockerHost::EventsListener stopped'
      end

      def restart
        stop
        start
      end
    end

    def initialize
      @last_event_time = {}
    end

    def listen
      log_reconnect if @reconnecting
      DockerHost.configure!

      Docker::Event.stream do |raw_event|
        process_event(DockerHost::Event.new(raw_event))
      end
    rescue Docker::Error::UnexpectedResponseError, Excon::Error::Socket
      # Stream interrupted - this is expected, reconnect after delay
      sleep 1
      @reconnecting = true
      retry
    rescue StandardError => e
      Rails.logger.error "DockerHost::EventsListener error: #{e.class}: #{e.message}"
      sleep 5
      @reconnecting = true
      retry
    end

    private

    def log_reconnect
      Rails.logger.debug { 'Docker event stream reconnecting...' }
    end

    def process_event(event)
      return unless event.relevant?

      Rails.logger.debug do
        "Docker event: #{event.action} for #{event.service_name}"
      end

      schedule_broadcast(event.service_name)
    end

    def schedule_broadcast(service_name)
      event_time = Time.current
      @last_event_time[service_name] = event_time

      Thread.new do
        sleep BROADCAST_DELAY

        # Skip if a newer event arrived
        next if @last_event_time[service_name] != event_time

        broadcast_status_update(service_name)
      end
    end

    def broadcast_status_update(service_name)
      Rails.application.reloader.wrap do
        DockerHost::Container.invalidate_cache
        container = DockerHost::Container.find(service_name)
        compose_service = Compose.load.services.find(service_name)

        # Always broadcast, even if container is nil (stopped/removed)
        return unless compose_service

        broadcast_service_row(service_name, container, compose_service)
        broadcast_service_status(service_name, container)
      end
    end

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
  end
end
