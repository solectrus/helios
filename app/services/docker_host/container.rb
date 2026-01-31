module DockerHost
  class Container
    class NotFoundError < StandardError
    end

    class << self
      def all(project: nil)
        DockerHost.configure!
        project ||= DockerHost.default_project
        return [] unless project

        docker_containers
          .select { |c| c.info.dig('Labels', COMPOSE_PROJECT_LABEL) == project }
          .map { |c| new(c) }
      rescue Excon::Error::Socket, Docker::Error::TimeoutError => e
        raise ConnectionError, "Cannot connect to Docker: #{e.message}"
      end

      def find(service_name, project: nil)
        DockerHost.configure!
        project ||= DockerHost.default_project
        return nil unless project

        container =
          docker_containers.find do |c|
            c.info.dig('Labels', COMPOSE_PROJECT_LABEL) == project &&
              c.info.dig('Labels', COMPOSE_SERVICE_LABEL) == service_name.to_s
          end

        container ? new(container) : nil
      rescue Excon::Error::Socket, Docker::Error::TimeoutError => e
        raise ConnectionError, "Cannot connect to Docker: #{e.message}"
      end

      private

      def docker_containers
        Docker::Container.all(all: true)
      end
    end

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

    def image_tag
      return nil unless image

      tag = image.split(':').last
      tag == image ? 'latest' : tag
    end

    def image_version
      @image_version ||= read_image_version
    end

    def read_image_version
      image_id = container.info['ImageID']
      return nil unless image_id

      DockerHost::Image.find(image_id)&.version
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

    def public_port
      # First try running container ports
      port_info = ports.find { |p| p['PublicPort'] }
      return port_info['PublicPort'] if port_info

      # Fallback to configured port bindings (works for stopped containers)
      port_bindings = container.json.dig('HostConfig', 'PortBindings') || {}
      first_binding = port_bindings.values.flatten.first
      first_binding&.dig('HostPort')&.to_i
    rescue Docker::Error::NotFoundError
      nil
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
      "#<DockerHost::Container #{service_name}: #{status}#{health}>"
    end
  end
end
