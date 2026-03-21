module Orchestration
  class ErrorStore
    ERRORS = Concurrent::Map.new

    class << self
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

      def clear_all
        ERRORS.clear
      end
    end
  end
end
