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

          DOCKER_EVENTS_STORAGE[:last_restart] = Time.current
          stop_instance(graceful: false)
          start_instance
        end
      end

      def running?
        instance&.running?
      end

      def subscriber_connected(locale: nil)
        class_mutex.synchronize do
          DOCKER_EVENTS_STORAGE[:subscriber_count] = subscriber_count + 1
          DOCKER_EVENTS_STORAGE[:locale] = locale if locale
          start_instance
        end
      end

      def locale
        DOCKER_EVENTS_STORAGE[:locale] || I18n.default_locale
      end

      def subscriber_disconnected
        class_mutex.synchronize do
          new_count = [subscriber_count - 1, 0].max
          DOCKER_EVENTS_STORAGE[:subscriber_count] = new_count
          stop_instance(graceful: false) if new_count.zero?
        end
      end

      def subscriber_count
        DOCKER_EVENTS_STORAGE[:subscriber_count] || 0
      end

      def reset_subscriber_count!
        class_mutex.synchronize { DOCKER_EVENTS_STORAGE[:subscriber_count] = 0 }
      end

      def initialize_lifecycle
        DOCKER_EVENTS_STORAGE[:mutex] ||= Mutex.new
      end

      # Called from the scheduler thread when no subscribers remain.
      # We cannot call instance.stop from a thread that belongs to the
      # instance (join would deadlock), so we just mark it stopped and
      # clear class state. The threads exit naturally via the running flag.
      def stop_abandoned(listener)
        class_mutex.synchronize do
          return unless instance == listener

          listener.mark_stopped!
          DOCKER_EVENTS_STORAGE[:subscriber_count] = 0
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
        last = DOCKER_EVENTS_STORAGE[:last_restart]
        last && Time.current - last < RESTART_COOLDOWN
      end

      def class_mutex
        DOCKER_EVENTS_STORAGE[:mutex] ||= Mutex.new
      end

      def instance
        DOCKER_EVENTS_STORAGE[:instance]
      end

      def instance=(value)
        DOCKER_EVENTS_STORAGE[:instance] = value
      end
    end

    attr_reader :id

    def initialize
      @id = SecureRandom.hex(4)
      @mutex = Mutex.new
      @pending_broadcasts = {}
      @running = Concurrent::AtomicBoolean.new(false)
      @broadcaster = ServiceBroadcaster.new(listener_id: id)
    end

    def start
      @running.make_true

      # rubocop:disable ThreadSafety/NewThread -- background threads are intentional
      self.listener_thread = Thread.new { listen_loop }
      listener_thread.name = "docker-events-#{id}"

      self.scheduler_thread = Thread.new { scheduler_loop }
      scheduler_thread.name = "docker-scheduler-#{id}"
      # rubocop:enable ThreadSafety/NewThread

      log_started
    end

    def stop(graceful: true)
      return unless @running.true? || threads_alive?

      was_running = @running.true?
      log_stopping if was_running
      @running.make_false
      join_threads(graceful:)
      log_stopped if was_running
    end

    def running?
      @running.true? && listener_thread&.alive?
    end

    def mark_stopped!
      @running.make_false
    end

    private

    attr_reader :mutex, :pending_broadcasts, :broadcaster
    attr_accessor :listener_thread, :scheduler_thread

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
      reconnecting = listen_once(reconnecting) while @running.true?
      log_loop_ended('Listener')
    end

    def listen_once(reconnecting)
      Orchestration::Connection.configure!
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
      still_running = @running.true?
      sleep delay if still_running
      still_running
    end

    def process_event(event)
      if event.relevant?
        log_event(event)
        schedule_broadcast(event.service_name, created: event.action == 'create')
      elsif event.helios_operation?
        log_event(event)
        broadcast_helios_operation
      end
    end

    # Backup/restore runners run as detached containers without compose labels,
    # so service-row broadcasts don't cover them. We push the status bar (so
    # the badge / restore mode tracks the container's lifecycle) and morph the
    # /backups page (so the in-progress row in the list disappears the moment
    # the container exits, instead of waiting for the 3 s auto-reload tick).
    # The refresh! re-syncs @service_statuses with the (possibly rewritten)
    # compose.yaml. A restore on a fresh host overwrites compose.yaml with
    # services that never produced container events, so without this they'd
    # be missing from the map and compute_overall would falsely report :ok
    # while several services are actually stopped.
    def broadcast_helios_operation
      BackupRunner.invalidate_in_progress_cache!
      RestoreRunner.invalidate_in_progress_cache!
      Orchestration::StackStatus.refresh!

      I18n.with_locale(self.class.locale) do
        Orchestration::StatusBarBroadcaster.new.broadcast
        Turbo::StreamsChannel.broadcast_refresh_to('backups')
      end
    rescue StandardError => e
      logger.error("[#{id}] Helios operation broadcast failed: #{e.class}: #{e.message}")
    end

    def scheduler_loop
      initial_refresh
      tick = 0
      while @running.true?
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

    def schedule_broadcast(service_name, created: false)
      mutex.synchronize do
        existing = pending_broadcasts[service_name]
        pending_broadcasts[service_name] = {
          due_at: Time.current + BROADCAST_DELAY,
          retries: 0,
          created: created || existing&.dig(:created),
        }
      end
    end

    def process_pending_broadcasts
      collect_due_broadcasts.each do |name, entry|
        execute_broadcast(name, retries: entry[:retries], created: entry[:created])
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

    def execute_broadcast(service_name, retries: 0, created: false)
      if broadcaster.broadcast(service_name, created:)
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
