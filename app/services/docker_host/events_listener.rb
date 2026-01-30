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
      DockerHost.configure!

      Docker::Event.stream { |raw_event| process_event(Event.new(raw_event)) }
    rescue Docker::Error::UnexpectedResponseError, Excon::Error::Socket => e
      # Stream interrupted - this is expected, reconnect silently
      Rails.logger.debug { "Docker event stream interrupted: #{e.message}" }
      sleep 1
      retry
    rescue StandardError => e
      Rails.logger.error "DockerHost::EventsListener error: #{e.class}: #{e.message}"
      sleep 5
      retry
    end

    private

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
      container = Container.find(service_name)
      return unless container

      compose_service = Compose.load.services.find(service_name)
      html = render_service_row(service_name, container, compose_service)

      Turbo::StreamsChannel.broadcast_replace_to(
        'services',
        target: "service-#{service_name}",
        html: html,
      )
    end

    def render_service_row(_service_name, container, compose_service)
      Rails.application.reloader.wrap do
        ApplicationController.render(
          ServiceRow::Component.new(
            compose_service:,
            container:,
            host: 'localhost',
            pending: false,
          ),
        )
      end
    end
  end
end
