module DockerHost
  module VersionExtractor
    class Redis < Base
      def match?
        image.include?('redis')
      end

      # Redis 8+ no longer sets REDIS_VERSION or REDIS_DOWNLOAD_URL as ENV;
      # these are now build-time ARGs only. Ask the server directly instead.
      def extract
        cache_key = "redis_version:#{container.id}"

        Rails
          .cache
          .fetch(cache_key) do
            stdout, _stderr, exit_code =
              container.exec(%w[redis-server --version])
            next unless exit_code&.zero?

            stdout.join[/v=(\d+\.\d+\.\d+)/, 1]
          rescue StandardError
            nil
          end
      end
    end
  end
end
