module Orchestration
  class Connection
    SOCKET_PATHS = [
      '/var/run/docker.sock',
      ::File.expand_path('~/.docker/run/docker.sock'),
    ].freeze

    # Minimum Docker Engine version HELIOS supports. Older daemons
    # miss features the generated compose.yaml relies on (e.g. the
    # Compose Spec layout, `docker compose config --hash`).
    MIN_ENGINE_VERSION = Gem::Version.new('24.0').freeze

    class << self
      def configure!
        socket = SOCKET_PATHS.find { |path| ::File.exist?(path) }
        Docker.url = "unix://#{socket}" if socket
      end

      def connected?
        configure!
        Docker.ping == 'OK'
      rescue StandardError
        false
      end

      ENGINE_VERSION_CACHE_KEY = 'orchestration/engine_version'.freeze

      # Docker Engine version as Gem::Version, or nil if the daemon is
      # unreachable. Cached for 1 hour — the daemon version only changes
      # on host upgrade, which requires a HELIOS restart anyway.
      def engine_version
        Rails.cache.fetch(ENGINE_VERSION_CACHE_KEY, expires_in: 1.hour) do
          fetch_engine_version
        end
      end

      private

      def fetch_engine_version
        configure!
        raw = Docker.version['Version']
        Gem::Version.new(raw) if raw
      rescue StandardError
        nil
      end
    end
  end
end
