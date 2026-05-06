module Orchestration
  # Tracks which services have a long-running compose action in flight
  # (e.g. recreate, start, stop). Set by the controller as soon as the
  # user triggers the action so any subsequent rendering — polling,
  # event broadcasts, full-page reload — keeps showing the pending
  # state instead of revealing the still-running old container.
  # Cleared by ComposeJob#ensure once the action finishes.
  class PendingOperations
    OPERATIONS = Concurrent::Map.new

    class << self
      def set(service_name, operation)
        OPERATIONS[service_name.to_s] = operation.to_sym
      end

      def get(service_name)
        OPERATIONS[service_name.to_s]
      end

      def clear(service_name)
        OPERATIONS.delete(service_name.to_s)
      end

      def each_key(&)
        OPERATIONS.each_key(&)
      end

      def clear_all
        OPERATIONS.clear
      end
    end
  end
end
