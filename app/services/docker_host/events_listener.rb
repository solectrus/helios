module DockerHost
  class EventsListener
    include Logging

    # Debounce delay: wait this long after the last event before broadcasting.
    # Multiple rapid events for the same service are merged into one broadcast.
    BROADCAST_DELAY = 0.5

    # How often the scheduler checks for due broadcasts.
    # Max latency = BROADCAST_DELAY + SCHEDULER_INTERVAL (currently 1.5s)
    SCHEDULER_INTERVAL = 1.0

    class << self
      include FileLock

      def start
        class_mutex.synchronize do
          if instance&.running?
            Logging.logger.info("Already running (#{instance.id})")
            return
          end

          # Acquire file lock to prevent multiple processes from running listeners
          unless try_acquire_file_lock
            Logging.logger.info('Another process holds the lock, skipping')
            return
          end

          instance&.stop
          new_instance = new
          new_instance.start
          self.instance = new_instance
        end
      end

      def stop
        class_mutex.synchronize do
          return unless instance

          instance.stop
          self.instance = nil
          release_file_lock
        end
      end

      def restart
        stop
        start
      end

      def running?
        instance&.running?
      end

      private

      def class_mutex
        storage[:mutex] ||= Mutex.new
      end

      def instance
        storage[:instance]
      end

      def instance=(value)
        storage[:instance] = value
      end

      def storage
        # Store in Rails app instance variable to survive code reloading
        Rails.application.instance_variable_get(:@docker_events_listener) ||
          Rails.application.instance_variable_set(:@docker_events_listener, {})
      end
    end

    attr_reader :id

    def initialize
      @id = SecureRandom.hex(4)
      @mutex = Mutex.new
      @pending_broadcasts = {}
      @running = false
      @broadcaster = ServiceBroadcaster.new(listener_id: id)
    end

    def start
      self.running = true

      # rubocop:disable ThreadSafety/NewThread -- background threads are intentional
      self.listener_thread = Thread.new { listen_loop }
      listener_thread.name = "docker-events-#{id}"

      self.scheduler_thread = Thread.new { scheduler_loop }
      scheduler_thread.name = "docker-scheduler-#{id}"
      # rubocop:enable ThreadSafety/NewThread

      log_started
    end

    def stop
      return unless running

      log_stopping
      self.running = false

      listener_thread&.join(2)
      scheduler_thread&.join(1)

      force_kill_threads
      log_stopped
    end

    def running?
      running && listener_thread&.alive?
    end

    private

    attr_reader :mutex, :pending_broadcasts, :broadcaster
    attr_accessor :running, :listener_thread, :scheduler_thread

    def force_kill_threads
      [listener_thread, scheduler_thread].each do |thread|
        next unless thread&.alive?

        thread.kill
        logger.warn("[#{id}] Thread #{thread.name} force killed")
      end
    end

    def listen_loop
      reconnecting = false
      reconnecting = listen_once(reconnecting) while running
      log_loop_ended('Listener')
    end

    def listen_once(reconnecting)
      log_reconnect if reconnecting
      DockerHost.configure!
      stream_events
      false
    rescue Docker::Error::UnexpectedResponseError, Excon::Error::Socket => e
      handle_stream_error(e, 1)
    rescue StandardError => e
      handle_stream_error(e, 5)
    end

    def handle_stream_error(error, delay)
      log_stream_error(error, delay)
      sleep delay if running
      running
    end

    def stream_events
      log_connecting

      Docker::Event.stream do |raw_event|
        break unless running

        process_event(DockerHost::Event.new(raw_event))
      end
    end

    def scheduler_loop
      while running
        sleep SCHEDULER_INTERVAL
        process_pending_broadcasts
      end

      log_loop_ended('Scheduler')
    end

    def process_event(event)
      return unless event.relevant?

      log_event(event)
      schedule_broadcast(event.service_name)
    end

    def schedule_broadcast(service_name)
      mutex.synchronize do
        pending_broadcasts[service_name] = Time.current + BROADCAST_DELAY
      end
    end

    def process_pending_broadcasts
      services = collect_due_broadcasts
      services.each { |name| execute_broadcast(name) }
    end

    def collect_due_broadcasts
      now = Time.current

      mutex.synchronize do
        due = pending_broadcasts.select { |_, time| time <= now }.keys
        due.each { |name| pending_broadcasts.delete(name) }
        due
      end
    end

    def execute_broadcast(service_name)
      return unless broadcaster.broadcast(service_name)

      log_broadcast(service_name)
    end
  end
end
