module Compose
  class ServiceStore
    ERRORS = Concurrent::Map.new
    PENDING = Concurrent::Map.new

    class << self
      # Error tracking
      def set(service_name, message)
        ERRORS[service_name.to_s] = message
      end

      def get(service_name)
        ERRORS[service_name.to_s]
      end

      def clear(service_name)
        ERRORS.delete(service_name.to_s)
      end

      def each_key(&)
        ERRORS.each_key(&)
      end

      # Pending tracking
      def mark_pending(service_name)
        PENDING[service_name.to_s] = true
      end

      def pending?(service_name)
        PENDING[service_name.to_s] == true
      end

      def clear_pending(service_name)
        PENDING.delete(service_name.to_s)
      end

      def clear_all_pending
        PENDING.clear
      end

      # Clear everything
      def clear_all
        ERRORS.clear
        PENDING.clear
      end
    end
  end
end
