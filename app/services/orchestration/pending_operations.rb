module Orchestration
  # Tracks which services have a long-running compose action in flight
  # (e.g. recreate, start, stop). Set by the controller as soon as the
  # user triggers the action so any subsequent rendering — polling,
  # event broadcasts, full-page reload — keeps showing the pending
  # state instead of revealing the still-running old container.
  # Cleared by ComposeJob#ensure once the action finishes.
  class PendingOperations
    OPERATIONS = Concurrent::Map.new

    # Operations that bring a container up. Used by StackStatus to keep
    # the status bar in :starting while consecutive single-service starts
    # are still queued — without this the bar flickers back to :partial
    # in the gap between one ComposeJob finishing and the next picking up.
    START_OPERATIONS = %i[start recreate upgrade up].freeze

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

      def any_start_pending?
        OPERATIONS.each_pair { |_, op| return true if START_OPERATIONS.include?(op) }
        false
      end
    end
  end
end
