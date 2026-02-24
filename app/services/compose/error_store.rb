module Compose
  class ErrorStore
    STORE = Concurrent::Map.new

    class << self
      def set(service_name, message)
        STORE[service_name.to_s] = message
      end

      def get(service_name)
        STORE[service_name.to_s]
      end

      def clear(service_name)
        STORE.delete(service_name.to_s)
      end

      def clear_all
        STORE.clear
      end

      def each_key(&)
        STORE.each_key(&)
      end
    end
  end
end
