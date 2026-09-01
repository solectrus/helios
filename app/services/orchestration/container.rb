module Orchestration
  class Container
    class NotFoundError < StandardError
    end

    # The cache is primarily kept fresh by the Docker events listener, which
    # invalidates on every state change (start/stop/health). This TTL is only a
    # fallback for missed events (e.g. during a listener restart), so it can be
    # generous — a short TTL just adds redundant inspects on slow hosts.
    CACHE_TTL = 15.seconds
    LIST_CACHE_KEY = 'docker_containers'.freeze
    INSPECT_CACHE_PREFIX = 'docker_inspect'.freeze
    INSPECT_GENERATION_KEY = 'docker_inspect_generation'.freeze

    # Coalesces concurrent cold-cache misses on the container list: the ~N
    # simultaneous row requests from a lazy-loaded /services page would each
    # run Docker::Container.all otherwise (Rails.cache.fetch does not dedupe
    # concurrent misses). The first request fetches under the lock; the rest
    # block briefly and then read the freshly populated cache.
    LIST_FETCH_MUTEX = Mutex.new

    # Restarts by the restart policy before a container counts as crash
    # looping. Docker holds a failing container in `restarting` between
    # attempts, so one or two are still a normal recovery — three in a row
    # mean the service never gets past its own start.
    CRASH_LOOP_RESTARTS = 3

    # How long a container has to stay free of exits before it counts as
    # recovered. Docker's restart backoff starts at 100 ms and only grows, so
    # a service that dies a second or two into its boot spends most of the
    # first minute in `running` — long enough to look healthy while it is in
    # fact looping.
    CRASH_LOOP_SETTLED = 60.seconds

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
        # Fast path: serve a warm cache without contending for the lock.
        cached = Rails.cache.read(LIST_CACHE_KEY)
        return cached unless cached.nil?

        # Slow path: coalesce so concurrent misses trigger a single Docker call.
        LIST_FETCH_MUTEX.synchronize do
          Rails
            .cache
            .fetch(LIST_CACHE_KEY, expires_in: CACHE_TTL) do
              Docker::Container.all(all: true)
            end
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

    # The image reference the container was created with, e.g.
    # `postgres:15-alpine`. Unlike #image this survives the tag moving on to a
    # newly pulled image, where the container list reports a bare `sha256:`
    # digest instead. #image stays right for spotting a container that runs an
    # older build than its service configures — that needs the digest.
    def configured_image = inspect_data&.dig('Config', 'Image').presence || image

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

    # How often the restart policy has brought this container back after it
    # exited. Docker keeps the count over the life of the container: a start
    # out of `restarting` carries it over, and only a start out of `exited`
    # clears it. On its own the count therefore says that the container died
    # this often at some point, never that it is dying now. #crash_looping? is
    # what adds the "now".
    def restart_count
      inspect_data&.dig('RestartCount').to_i
    end

    # Container is caught in a restart loop rather than merely starting up.
    # Docker reports both as `restarting`, which is why the count has to
    # decide: a single failed start is a hiccup the next attempt may well
    # fix, while a service that has died this often needs the user to look
    # at its log.
    #
    # A looping container is not always caught between two attempts. Docker
    # reports it as `running` for as long as it survives each time, so the
    # running half asks how long ago the container last died.
    def crash_looping?
      return false if restart_count < CRASH_LOOP_RESTARTS

      status == 'restarting' || (running? && died_recently?)
    end

    def effective_status
      return :stopped unless running?

      hs = health_status
      return :starting if hs == 'starting'
      return :error if hs && hs != 'healthy'
      return :starting if hs.nil? && healthcheck_configured?

      :ok
    end

    # Docker reports `unhealthy` for a container it simply could not probe, not
    # only for one that failed a probe: pausing a container stops its health
    # monitor and flips the status, and after `unpause` it stays that way until
    # a full interval has elapsed. The failing streak tells the two apart — it
    # stays at zero when no probe ever failed, while a genuine fault has counted
    # at least one failure.
    #
    # Which of the two harmless cases it is, the probe log answers: it survives
    # the pause, so a container that was passing when it was frozen still has
    # that result on record and is reported healthy the moment it is thawed,
    # instead of dragging the whole stack to `starting` for an entire interval
    # after every update pause (see UpdatePause). An empty log means nothing was
    # ever probed — a freshly started container, which `starting` describes.
    def health_status
      raw = inspect_data&.dig('State', 'Health', 'Status')
      return raw unless raw == 'unhealthy' && failing_streak.zero?

      last_probe_exit_code&.zero? ? 'healthy' : 'starting'
    end

    def failing_streak
      inspect_data&.dig('State', 'Health', 'FailingStreak').to_i
    end

    # Docker keeps the last five probe results; the most recent one is what the
    # frozen status was computed from.
    def last_probe_exit_code
      log = inspect_data&.dig('State', 'Health', 'Log')
      log&.last&.dig('ExitCode')
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

    # Sends a Unix signal to the container's main process (`docker kill
    # --signal`), for services that expose an action through a signal handler
    # — e.g. the power-splitter's USR1 recalculation. Despite the name this
    # does not terminate the container unless the signal says so.
    def kill(signal:)
      raw_container.kill!('signal' => signal.to_s)
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

    # Whether the container's last exit is recent enough to still belong to a
    # loop. It reads `FinishedAt`, the end of the previous run, and not
    # `StartedAt`, the beginning of the current one, because only the exit
    # says that the container is still dying.
    #
    # The two part company after a host reboot: the daemon brings the stack up
    # through the restart policy, which moves `StartedAt` to boot time and
    # leaves `RestartCount` at whatever an earlier loop left it. Read off
    # `StartedAt`, every service that ever looped would come back from a
    # reboot flagged for its first minute. `FinishedAt` stays on the exit
    # before the shutdown and reads as long recovered. In a real loop the two
    # are milliseconds apart, so nothing is lost by asking the exit instead.
    #
    # A container that never exited carries `0001-01-01T00:00:00Z` and so
    # reads as long recovered. A missing or unparsable time reads the same
    # way, so a container is never flagged on a value we cannot read.
    def died_recently?
      finished = inspect_data&.dig('State', 'FinishedAt')
      return false unless finished

      Time.current - Time.zone.parse(finished) < CRASH_LOOP_SETTLED
    rescue ArgumentError, TypeError
      false
    end

    # Inspect data is cached at two levels:
    # - Per-instance memoization for repeated reads inside one render
    #   (health_status + public_port + version on the same container).
    # - Cross-request via Rails.cache (CACHE_TTL, versioned by INSPECT_GENERATION_KEY)
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
