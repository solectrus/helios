module DockerHost
  class Image
    class Redis < Image
      def self.identifier
        'redis'
      end

      def version
        url = env_value('REDIS_DOWNLOAD_URL')
        url&.[](%r{/(\d+\.\d+\.\d+)\.tar}, 1)
      end
    end
  end
end
