module Orchestration
  class EventsListener # rubocop:disable Metrics/ClassLength
    include Logging
    include Streaming

    BROADCAST_DELAY = 0.5
    SCHEDULER_INTERVAL = 1.0
    MAX_BROADCAST_RETRIES = 3 # Exponential backoff: 1s, 2s, 4s
    RESTART_COOLDOWN = 5.seconds
    RECONCILE_TICKS = 30

    class << self
      def start
        class_mutex.synchronize { start_instance }
      end

      def stop
        class_mutex.synchronize { stop_instance }
      end

      def restart
        class_mutex.synchronize do
          next if recently_restarted?

          storage[:last_restart] = Time.current
          stop_instance(graceful: false)
          start_instance
        end
      end

      def running?
        instance&.running?
      end

      def subscriber_connected(locale: nil)
        class_mutex.synchronize do
          storage[:subscriber_count] = subscriber_count + 1
          storage[:locale] = locale if locale
          start_instance
        end
      end

      def locale
        storage[:locale] || I18n.default_locale
      end

      def subscriber_disconnected
        class_mutex.synchronize do
          new_count = [subscriber_count - 1, 0].max
          storage[:subscriber_count] = new_count
          stop_instance(graceful: false) if new_count.zero?
        end
      end

      def subscriber_count
        storage[:subscriber_count] || 0
      end

      def reset_subscriber_count!
        class_mutex.synchronize { storage[:subscriber_count] = 0 }
      end

      def initialize_lifecycle
        storage[:mutex] ||= Mutex.new
      end

      # Called from the scheduler thread when no subscribers remain.
      # We cannot call instance.stop from a thread that belongs to the
      # instance (join would deadlock), so we just mark it stopped and
      # clear class state. The threads exit naturally via the running flag.
      def stop_abandoned(listener)
        class_mutex.synchronize do
          return unless instance == listener

          listener.send(:running=, false)
          storage[:subscriber_count] = 0
          self.instance = nil
        end
      end

      private

      def start_instance
        return if instance&.running?

        instance&.stop
        new_instance = new
        new_instance.start
        self.instance = new_instance
      end

      def stop_instance(graceful: true)
        return unless instance

        instance.stop(graceful:)
        self.instance = nil
      end

      def recently_restarted?
        last = storage[:last_restart]
        last && Time.current - last < RESTART_COOLDOWN
      end

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

    def stop(graceful: true)
      return unless running || threads_alive?

      was_running = running
      log_stopping if was_running
      self.running = false
      join_threads(graceful:)
      log_stopped if was_running
    end

    def running?
      running && listener_thread&.alive?
    end

    private

    attr_reader :mutex, :pending_broadcasts, :broadcaster
    attr_accessor :running, :listener_thread, :scheduler_thread

    def threads_alive?
      listener_thread&.alive? || scheduler_thread&.alive?
    end

    def join_threads(graceful:)
      scheduler_thread&.wakeup rescue nil # rubocop:disable Style/RescueModifier
      scheduler_thread&.join(2)
      listener_thread&.join(2) if graceful
      kill_thread(listener_thread)
      kill_thread(scheduler_thread)
    end

    def kill_thread(thread)
      return unless thread&.alive?

      thread.kill
      logger.debug("[#{id}] Thread #{thread.name} force killed")
    end

    def listen_loop
      reconnecting = false
      reconnecting = listen_once(reconnecting) while running
      log_loop_ended('Listener')
    end

    def listen_once(reconnecting)
      Orchestration.configure!
      if reconnecting
        log_reconnect
        Orchestration::StackStatus.refresh!
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

    def process_event(event)
      return unless event.relevant?

      log_event(event)
      schedule_broadcast(event.service_name)
    end

    def scheduler_loop
      initial_refresh
      tick = 0
      while running
        sleep SCHEDULER_INTERVAL
        run_scheduler_tick
        tick += 1
        if (tick % RECONCILE_TICKS).zero?
          reconcile_subscribers
          tick = 0
        end
      end

      log_loop_ended('Scheduler')
    end

    def initial_refresh
      Orchestration::StackStatus.refresh!
    rescue StandardError => e
      logger.error("[#{id}] Initial refresh: #{e.class}: #{e.message}")
    end

    def reconcile_subscribers
      return unless subscribers_drifted?

      logger.info("[#{id}] No active connections, stopping")
      # Can't call instance stop from the scheduler thread (ThreadError
      # on self-join). Signal both loops to exit and clear class state
      # so the next subscriber_connected creates a fresh instance.
      self.class.stop_abandoned(self)
    rescue StandardError => e
      logger.debug("[#{id}] Reconciliation: #{e.class}: #{e.message}")
    end

    def subscribers_drifted?
      ActionCable.server.connections.empty? && self.class.subscriber_count.positive?
    end

    def run_scheduler_tick
      process_pending_broadcasts
    rescue StandardError => e
      logger.error("[#{id}] Scheduler: #{e.class}: #{e.message}")
    end

    def schedule_broadcast(service_name)
      mutex.synchronize do
        pending_broadcasts[service_name] = {
          due_at: Time.current + BROADCAST_DELAY,
          retries: 0,
        }
      end
    end

    def process_pending_broadcasts
      collect_due_broadcasts.each do |name, entry|
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
