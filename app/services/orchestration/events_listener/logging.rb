module Orchestration
  class EventsListener
    module Logging
      LOG_PATH = 'log/docker_events.log'.freeze

      def self.logger
        LOGGER
      end

      LOGGER =
        ActiveSupport::Logger
        .new(Rails.root.join(LOG_PATH), 5, 10.megabytes)
        .tap do |log|
          log.formatter =
            proc do |severity, time, _, msg|
              "[#{time.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
            end
        end
      private_constant :LOGGER

      private

      def logger
        Orchestration::EventsListener::Logging.logger
      end

      def log_started
        logger.info(
          "[#{id}] Started (#{listener_thread.name}, #{scheduler_thread.name})",
        )
      end

      def log_stopping
        logger.info("[#{id}] Stopping...")
      end

      def log_stopped
        logger.info("[#{id}] Stopped")
      end

      def log_reconnect
        logger.info("[#{id}] Reconnecting...")
      end

      def log_stream_error(error, delay)
        logger.warn(
          "[#{id}] Stream error: #{error.class}: #{error.message} (retry in #{delay}s)",
        )
      end

      def log_event(event)
        logger.debug("[#{id}] Event: #{event.action} for #{event.service_name}")
      end

      def log_broadcast(service_name)
        logger.debug("[#{id}] Broadcast for #{service_name}")
      end

      def log_loop_ended(name)
        logger.debug("[#{id}] #{name} loop ended")
      end

      def log_connecting
        logger.debug("[#{id}] Connecting to Docker event stream...")
      end
    end
  end
end
