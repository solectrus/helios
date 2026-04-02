module Orchestration
  class EventsListener
    # Buffered Docker event streaming.
    # Replaces Docker::Event.stream which uses each_line on raw HTTP chunks,
    # yielding partial JSON when an event spans multiple chunks.
    module Streaming
      private

      def stream_events
        log_connecting

        buffer = +''
        Docker.connection.get(
          '/events', {},
          response_block: lambda { |chunk, _remaining, _total|
            next unless @running.true?

            process_chunk(buffer, chunk)
          }
        )
      end

      def process_chunk(buffer, chunk)
        buffer << chunk
        return overflow_reset(buffer) if buffer.size > 1.megabyte

        while @running.true? && (idx = buffer.index("\n"))
          line = buffer.slice!(0, idx + 1)
          raw_event = parse_event(line)
          process_event(Orchestration::Event.new(raw_event)) if raw_event
        end
      end

      def overflow_reset(buffer)
        logger.error("[#{id}] Event buffer overflow, resetting")
        buffer.clear
      end

      def parse_event(line)
        return if line.blank?

        Docker::Event.new(JSON.parse(line))
      rescue JSON::ParserError => e
        logger.warn("[#{id}] Malformed event JSON: #{e.message}")
        nil
      end
    end
  end
end
