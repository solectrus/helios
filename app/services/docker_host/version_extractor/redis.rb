module DockerHost
  module VersionExtractor
    class Redis < Base
      def match?
        image.include?('redis')
      end

      def extract
        url = env_value('REDIS_DOWNLOAD_URL')
        url&.[](%r{/(\d+\.\d+\.\d+)\.tar}, 1)
      end
    end
  end
end
