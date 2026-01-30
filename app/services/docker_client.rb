require 'docker-api'
require 'yaml'

class DockerClient
  class ConnectionError < StandardError
  end

  class ContainerNotFound < StandardError
  end

  COMPOSE_PROJECT_LABEL = 'com.docker.compose.project'.freeze
  COMPOSE_SERVICE_LABEL = 'com.docker.compose.service'.freeze

  SOCKET_PATHS = [
    '/var/run/docker.sock',
    File.expand_path('~/.docker/run/docker.sock'),
  ].freeze

  class << self
    def containers(project: nil)
      configure_docker!
      project ||= default_project
      return [] unless project

      all_containers
        .select do |container|
          container.info.dig('Labels', COMPOSE_PROJECT_LABEL) == project
        end
        .map { |c| ContainerInfo.new(c) }
    rescue Excon::Error::Socket, Docker::Error::TimeoutError => e
      raise ConnectionError, "Cannot connect to Docker: #{e.message}"
    end

    def find(service_name, project: nil)
      configure_docker!
      project ||= default_project
      return nil unless project

      container =
        all_containers.find do |c|
          c.info.dig('Labels', COMPOSE_PROJECT_LABEL) == project &&
            c.info.dig('Labels', COMPOSE_SERVICE_LABEL) == service_name.to_s
        end

      container ? ContainerInfo.new(container) : nil
    rescue Excon::Error::Socket, Docker::Error::TimeoutError => e
      raise ConnectionError, "Cannot connect to Docker: #{e.message}"
    end

    def connected?
      configure_docker!
      Docker.ping == 'OK'
    rescue StandardError
      false
    end

    def default_project
      ENV.fetch('COMPOSE_PROJECT_NAME', nil) || project_from_stack_path
    end

    private

    def configure_docker!
      return if @configured

      socket = SOCKET_PATHS.find { |path| File.exist?(path) }
      Docker.url = "unix://#{socket}" if socket
      @configured = true
    end

    def all_containers
      Docker::Container.all(all: true)
    end

    def project_from_stack_path
      stack_path = Rails.configuration.helios_stack_path
      return nil unless stack_path

      # Try to read project name from compose.yaml
      compose_file = File.join(stack_path, 'compose.yaml')
      if File.exist?(compose_file)
        compose = YAML.safe_load_file(compose_file)
        return compose['name'] if compose['name']
      end

      # Fallback to directory name
      File.basename(stack_path)
    end
  end

  class ContainerInfo
    attr_reader :container

    def initialize(container)
      @container = container
    end

    delegate :id, to: :container

    def name
      container.info['Names']&.first&.delete_prefix('/')
    end

    def service_name
      container.info.dig('Labels', COMPOSE_SERVICE_LABEL)
    end

    def image
      container.info['Image']
    end

    def status
      container.info['State']
    end

    def running?
      status == 'running'
    end

    def health_status
      container.json.dig('State', 'Health', 'Status')
    rescue Docker::Error::NotFoundError
      nil
    end

    def healthy?
      health_status == 'healthy'
    end

    def logs(tail: 100, timestamps: false)
      opts = { stdout: true, stderr: true, tail: tail, timestamps: timestamps }
      container.logs(opts)
    rescue Docker::Error::NotFoundError
      nil
    end

    def created_at
      Time.zone.parse(container.info['Created'])
    end

    def ports
      container.info['Ports'] || []
    end

    def to_h
      {
        id: id,
        name: name,
        service_name: service_name,
        image: image,
        status: status,
        health_status: health_status,
      }
    end

    def inspect
      health = health_status ? " (#{health_status})" : ''
      "#<Container #{service_name}: #{status}#{health}>"
    end
  end
end
