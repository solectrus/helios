module Orchestration
  class Container
    class NotFoundError < StandardError
    end

    CACHE_TTL = 3.seconds
    LIST_CACHE_KEY = 'docker_containers'.freeze
    INSPECT_CACHE_PREFIX = 'docker_inspect'.freeze
    INSPECT_GENERATION_KEY = 'docker_inspect_generation'.freeze

    class << self
      def all(project: nil)
        with_docker_connection(project:) do |proj|
          project_containers(proj).map { |c| new(c) }
        end || []
      end

      def find(service_name, project: nil)
        with_docker_connection(project:) do |proj|
          raw =
            project_containers(proj).find do |c|
              c.info.dig('Labels', COMPOSE_SERVICE_LABEL) == service_name.to_s
            end

          raw ? new(raw) : nil
        end
      end

      # Drops both the container list and all cached container inspects.
      # Inspects are versioned via a generation key — bumping it makes the
      # previous keys unreachable so a Docker event (start/stop/health) forces
      # a fresh inspect on the next read, even when the container ID is reused.
      def invalidate_cache
        Rails.cache.delete(LIST_CACHE_KEY)
        Rails.cache.write(INSPECT_GENERATION_KEY, Time.current.to_f)
      end

      def inspect_generation
        Rails.cache.fetch(INSPECT_GENERATION_KEY) { 0 }
      end

      private

      def with_docker_connection(project: nil)
        Orchestration::Connection.configure!
        project ||= Orchestration::PROJECT_NAME
        return nil unless project

        yield(project)
      rescue Excon::Error::Socket, Docker::Error::TimeoutError => e
        raise ConnectionError, "Cannot connect to Docker: #{e.message}"
      end

      def project_containers(project)
        fetch_all_containers
          .select { |c| c.info.dig('Labels', COMPOSE_PROJECT_LABEL) == project }
      end

      def fetch_all_containers
        Rails
          .cache
          .fetch(LIST_CACHE_KEY, expires_in: CACHE_TTL) do
            Docker::Container.all(all: true)
          end
      end
    end

    def initialize(raw_container)
      @raw_container = raw_container
    end

    delegate :id, :info, to: :raw_container

    # Mirrors Docker::Container#json but reads through our cached inspect data.
    # Lets VersionExtractor work against our wrapper without bypassing the
    # cross-request inspect cache.
    def json
      inspect_data
    end

    def name
      raw_container.info['Names']&.first&.delete_prefix('/')
    end

    def service_name
      raw_container.info.dig('Labels', COMPOSE_SERVICE_LABEL)
    end

    def image
      raw_container.info['Image']
    end

    def config_hash
      raw_container.info.dig('Labels', COMPOSE_CONFIG_HASH_LABEL)
    end

    def image_tag
      return nil unless image

      tag = image.split(':').last
      tag == image ? 'latest' : tag
    end

    def version
      @version ||= VersionExtractor.extract(self)
    rescue Docker::Error::DockerError, Excon::Error
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

    # Runs a command inside the container, returning [stdout, stderr, exit_code].
    def exec(command, **)
      raw_container.exec(command, **)
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

    # Host path for a given mount destination inside the container.
    # Returns nil if the destination is not mounted.
    def mount_source(destination)
      mount = inspect_data&.dig('Mounts')&.find { |m| m['Destination'] == destination }
      mount&.dig('Source')
    end

    def stop_and_remove!
      raw_container.stop
      raw_container.remove
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

    # Inspect data is cached at two levels:
    # - Per-instance memoization for repeated reads inside one render
    #   (health_status + public_port + version on the same container).
    # - Cross-request via Rails.cache (3s TTL, versioned by INSPECT_GENERATION_KEY)
    #   so the N concurrent row requests triggered by lazy-loaded /services
    #   share one inspect per container instead of each hitting the Docker API.
    #   `Container.invalidate_cache` bumps the generation, so events that mutate
    #   state without changing the container ID (start/stop/health transitions)
    #   still surface fresh data on the next read.
    # Catches all Docker/network errors to prevent cascade failures when a
    # single container is temporarily unreachable.
    def inspect_data
      return @inspect_data if instance_variable_defined?(:@inspect_data)

      @inspect_data =
        Rails.cache.fetch(inspect_cache_key, expires_in: CACHE_TTL) do
          raw_container.json
        end
    rescue Docker::Error::DockerError, Excon::Error
      @inspect_data = nil
    end

    def inspect_cache_key
      "#{INSPECT_CACHE_PREFIX}/#{self.class.inspect_generation}/#{id}"
    end
  end
end
