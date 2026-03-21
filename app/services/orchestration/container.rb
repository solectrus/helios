module Orchestration
  class Container
    class NotFoundError < StandardError
    end

    CACHE_TTL = 3.seconds

    class << self
      def all(project: nil)
        Orchestration::Connection.configure!
        project ||= Orchestration.default_project
        return [] unless project

        fetch_all_containers
          .select { |c| c.info.dig('Labels', COMPOSE_PROJECT_LABEL) == project }
          .map { |c| new(c) }
      rescue Excon::Error::Socket, Docker::Error::TimeoutError => e
        raise ConnectionError, "Cannot connect to Docker: #{e.message}"
      end

      def find(service_name, project: nil)
        Orchestration::Connection.configure!
        project ||= Orchestration.default_project
        return nil unless project

        raw =
          fetch_all_containers.find do |c|
            c.info.dig('Labels', COMPOSE_PROJECT_LABEL) == project &&
              c.info.dig('Labels', COMPOSE_SERVICE_LABEL) == service_name.to_s
          end

        raw ? new(raw) : nil
      rescue Excon::Error::Socket, Docker::Error::TimeoutError => e
        raise ConnectionError, "Cannot connect to Docker: #{e.message}"
      end

      def invalidate_cache
        Rails.cache.delete('docker_containers')
      end

      private

      def fetch_all_containers
        Rails
          .cache
          .fetch('docker_containers', expires_in: CACHE_TTL) do
            Docker::Container.all(all: true)
          end
      end
    end

    def initialize(raw_container)
      @raw_container = raw_container
    end

    delegate :id, to: :raw_container

    def name
      raw_container.info['Names']&.first&.delete_prefix('/')
    end

    def service_name
      raw_container.info.dig('Labels', COMPOSE_SERVICE_LABEL)
    end

    def image
      raw_container.info['Image']
    end

    def image_tag
      return nil unless image

      tag = image.split(':').last
      tag == image ? 'latest' : tag
    end

    def version
      @version ||= VersionExtractor.extract(raw_container)
    rescue Docker::Error::NotFoundError
      nil
    end

    def status
      raw_container.info['State']
    end

    def running?
      status == 'running'
    end

    def stoppable?
      %w[running restarting paused].include?(status)
    end

    def effective_status
      return :stopped unless running?

      hs = health_status
      return :starting if hs == 'starting'
      return :error if hs && hs != 'healthy'
      return :starting if hs.nil? && healthcheck_configured?

      :ok
    end

    def health_status
      inspect_data&.dig('State', 'Health', 'Status')
    end

    def healthcheck_configured?
      inspect_data&.dig('State', 'Health').present?
    end

    def healthy?
      health_status == 'healthy'
    end

    def logs(tail: 100, timestamps: false)
      raw_container.logs(
        stdout: true,
        stderr: true,
        tail: tail,
        timestamps: timestamps,
      )
    rescue Docker::Error::NotFoundError
      nil
    end

    def created_at
      Time.zone.parse(raw_container.info['Created'])
    end

    def ports
      raw_container.info['Ports'] || []
    end

    def public_port
      # First try running container ports
      port_info = ports.find { |p| p['PublicPort'] }
      return port_info['PublicPort'] if port_info

      # Fallback to configured port bindings (works for stopped containers)
      port_bindings = inspect_data&.dig('HostConfig', 'PortBindings') || {}
      first_binding = port_bindings.values.flatten.first
      first_binding&.dig('HostPort')&.to_i
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
      "#<Orchestration::Container #{service_name}: #{status}#{health}>"
    end

    private

    attr_reader :raw_container

    # Cache inspect data per instance — avoids multiple Docker API calls
    # for health_status, public_port, etc. within a single operation.
    # Catches all Docker/network errors to prevent cascade failures
    # when a single container is temporarily unreachable.
    def inspect_data
      return @inspect_data if instance_variable_defined?(:@inspect_data)

      @inspect_data = raw_container.json
    rescue Docker::Error::DockerError, Excon::Error
      @inspect_data = nil
    end
  end
end
