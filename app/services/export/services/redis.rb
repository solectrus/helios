module Export
  module Services
    class Redis < Base
      def self.service_name
        'redis'
      end

      def self.comment
        'In-memory store for caching'
      end

      def self.data_directories
        ['redis']
      end

      def to_h
        {
          image: configuration.redis.image,
          volumes: ['./redis:/data'],
          restart: 'unless-stopped',
          healthcheck: healthcheck('CMD', 'redis-cli', 'ping'),
        }
      end
    end
  end
end
