module Export
  module Services
    class Redis < Base
      def self.service_name
        'redis'
      end

      def self.config_keys
        ['redis']
      end

      def self.volume_env_key
        'REDIS_VOLUME_PATH'
      end

      def self.comment
        'Redis — In-memory store for caching'
      end

      def self.enabled?(configuration)
        !configuration.collectors_only?
      end

      def data_directories
        managed_data_directory
      end

      def to_h
        {
          image: configuration.redis.image,
          environment: ['TZ'],
          volumes: [bind_mount('/data')],
          restart: 'unless-stopped',
          healthcheck: healthcheck('CMD', 'redis-cli', 'ping', timeout: '3s', retries: 3, start_period: '10s'),
        }
      end
    end
  end
end
