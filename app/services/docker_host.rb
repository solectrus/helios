require 'docker-api'

module DockerHost
  class ConnectionError < StandardError
  end

  COMPOSE_PROJECT_LABEL = 'com.docker.compose.project'.freeze
  COMPOSE_SERVICE_LABEL = 'com.docker.compose.service'.freeze

  SOCKET_PATHS = [
    '/var/run/docker.sock',
    ::File.expand_path('~/.docker/run/docker.sock'),
  ].freeze

  class << self
    def configure!
      return if @configured

      socket = SOCKET_PATHS.find { |path| ::File.exist?(path) }
      Docker.url = "unix://#{socket}" if socket
      @configured = true
    end

    def connected?
      configure!
      Docker.ping == 'OK'
    rescue StandardError
      false
    end

    def default_project
      ENV.fetch('COMPOSE_PROJECT_NAME', nil) || project_from_stack_path
    end

    private

    def project_from_stack_path
      stack_path = Rails.configuration.helios_stack_path
      return nil unless stack_path

      compose_file = ::File.join(stack_path, 'compose.yaml')
      return ::File.basename(stack_path) unless ::File.exist?(compose_file)

      config = YAML.safe_load_file(compose_file)
      config['name'] || ::File.basename(stack_path)
    end
  end
end
