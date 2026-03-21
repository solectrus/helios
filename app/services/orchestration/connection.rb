module Orchestration
  class Connection
    SOCKET_PATHS = [
      '/var/run/docker.sock',
      ::File.expand_path('~/.docker/run/docker.sock'),
    ].freeze

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
    end
  end
end
