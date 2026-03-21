module Export
  module Services
    class Base
      def initialize(configuration)
        @configuration = configuration
      end

      def self.enabled?(_configuration)
        true
      end

      def self.service_name
        raise NotImplementedError
      end

      def self.comment
        raise NotImplementedError
      end

      def self.data_directories
        []
      end

      private

      attr_reader :configuration

      def healthcheck(*test_cmd)
        { test: test_cmd, interval: '10s', timeout: '5s', retries: 5 }
      end

      def healthy_depends_on(services)
        services.index_with { { condition: 'service_healthy' } }
      end
    end
  end
end
