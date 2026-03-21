module Orchestration
  class EventsListener
    include Logging

    # Debounce delay: wait this long after the last event before broadcasting.
    # Multiple rapid events for the same service are merged into one broadcast.
    BROADCAST_DELAY = 0.5

    # How often the scheduler checks for due broadcasts.
    # Max latency = BROADCAST_DELAY + SCHEDULER_INTERVAL (currently 1.5s)
    SCHEDULER_INTERVAL = 1.0

    # Max retries for failed broadcasts (exponential backoff: 1s, 2s, 4s)
    MAX_BROADCAST_RETRIES = 3

    # Periodic full refresh to self-correct missed events or stale states.
    REFRESH_INTERVAL = 30.seconds

    # Delay before first periodic refresh — gives the listener time to connect
    # and containers time to complete health checks after startup.
    INITIAL_REFRESH_DELAY = 5.seconds

    class << self
      def start
        class_mutex.synchronize do
          if instance&.running?
            Logging.logger.info("Already running (#{instance.id})")
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
      Orchestration::StackStatus.refresh!
    end

    def stop
      return unless running

      log_stopping
      self.running = false

      # Wake up sleeping threads so they can exit immediately
      scheduler_thread&.wakeup rescue nil # rubocop:disable Style/RescueModifier
      listener_thread&.join(2)
      scheduler_thread&.join(2)

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
        logger.debug("[#{id}] Thread #{thread.name} force killed")
      end
    end

    # --- Listener thread ---
    #
    # Wraps each iteration in Rails.application.executor to ensure
    # proper constant autoloading and database connection management
    # in background threads.

    def listen_loop
      reconnecting = false
      reconnecting = listen_once(reconnecting) while running
      log_loop_ended('Listener')
    end

    def listen_once(reconnecting)
      Rails.application.executor.wrap do
        if reconnecting
          log_reconnect
          Orchestration::StackStatus.refresh!
        end
        Orchestration.configure!
      end
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

        Rails.application.executor.wrap do
          process_event(Orchestration::Event.new(raw_event))
        end
      end
    end

    def process_event(event)
      return unless event.relevant?

      log_event(event)
      schedule_broadcast(event.service_name)
    end

    # --- Scheduler thread ---

    def scheduler_loop
      @next_refresh = Time.current + INITIAL_REFRESH_DELAY

      while running
        sleep SCHEDULER_INTERVAL
        run_scheduler_tick
      end

      log_loop_ended('Scheduler')
    end

    def run_scheduler_tick
      Rails.application.executor.wrap do
        process_pending_broadcasts
        periodic_refresh
      end
    rescue StandardError => e
      logger.error("[#{id}] Scheduler error: #{e.class}: #{e.message}")
    end

    def periodic_refresh
      return unless Time.current >= @next_refresh

      interval =
        (
          if Orchestration::StackStatus.services_settling?
            Orchestration::StackStatus::ACTIVE_REFRESH_INTERVAL
          else
            REFRESH_INTERVAL
          end
        )
      @next_refresh = Time.current + interval
      Orchestration::StackStatus.refresh!
    end

    # --- Broadcast scheduling ---

    def schedule_broadcast(service_name)
      mutex.synchronize do
        pending_broadcasts[service_name] = {
          due_at: Time.current + BROADCAST_DELAY,
          retries: 0,
        }
      end
    end

    def process_pending_broadcasts
      due_broadcasts = collect_due_broadcasts
      due_broadcasts.each do |name, entry|
        execute_broadcast(name, retries: entry[:retries])
      end
    end

    def collect_due_broadcasts
      now = Time.current

      mutex.synchronize do
        due = pending_broadcasts.select { |_, entry| entry[:due_at] <= now }
        due.each_key { |name| pending_broadcasts.delete(name) }
        due
      end
    end

    def execute_broadcast(service_name, retries: 0)
      if broadcaster.broadcast(service_name)
        log_broadcast(service_name)
      else
        retry_broadcast(service_name, retries:)
      end
    end

    # Retry with exponential backoff (1s, 2s, 4s — max 3 retries)
    def retry_broadcast(service_name, retries:)
      return if retries >= MAX_BROADCAST_RETRIES

      delay = BROADCAST_DELAY * (2**(retries + 1))
      mutex.synchronize do
        pending_broadcasts[service_name] = {
          due_at: Time.current + delay,
          retries: retries + 1,
        }
      end
      logger.warn(
        "[#{id}] Broadcast failed for #{service_name}, retry #{retries + 1}/#{MAX_BROADCAST_RETRIES}",
      )
    end
  end
end
