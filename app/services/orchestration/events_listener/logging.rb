module Orchestration
  class EventsListener
    module Logging
      # The class tag ([Orchestration::EventsListener]) is applied centrally by
      # Loggable; the `#{id}` prefix below is per-instance data.

      private

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
