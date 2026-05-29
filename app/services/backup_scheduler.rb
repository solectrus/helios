# Fires automatic backups on a daily schedule (Issue #106).
#
# Runs as a single long-lived thread inside the Puma process. HELIOS runs
# single-mode Puma, so the thread exists exactly once. The thread only decides
# *when* to fire — the heavy lifting stays in the detached `BackupRunner`
# sidecar, exactly as for a manually triggered backup.
#
# Lifecycle is driven from config/puma.rb (`after_booted` / `after_stopped`) so the
# scheduler runs only inside the real server, never under rake, console or
# RSpec. State lives in the BACKUP_SCHEDULER_STORAGE constant (defined in the
# initializer) so it survives code reloading in development.
#
# Times are interpreted in the container's local timezone — the wall-clock
# time the user enters in the form is the wall-clock time HELIOS fires at.
#
# Dedup / catch-up: at most one automatic backup is handled per calendar day.
# The handled date is persisted to a small state file and stamped *up front*
# — the moment we decide to act, before launching the backup. This is what
# stops a 30 s retry storm: a transient failure (or the databases being down
# at the scheduled minute) still marks the day, so the loop won't keep
# re-trying every tick; the miss is surfaced in the log instead. Because the
# marker lives on disk, it also survives development code reloads (which spawn
# fresh scheduler threads) and process restarts. A window missed because
# HELIOS was down is caught up once on the next boot past the configured time.
#
# Concurrency: ticks are serialized process-wide through an atomic gate, so
# overlapping or leaked threads (e.g. from a dev-reload restart storm) can
# never fire two backups at once.
class BackupScheduler < ManagedThread
  TICK_INTERVAL = 30 # seconds

  # Persisted marker for the last calendar day the schedule was handled.
  # Lives in HELIOS's data dir next to the other runtime state.
  STATE_FILENAME = 'backup_schedule_last_run'.freeze

  class << self
    def storage
      BACKUP_SCHEDULER_STORAGE
    end

    def initialize_lifecycle
      # Eagerly build the shared primitives during single-threaded boot so the
      # lazy `||=` in class_mutex / tick_gate never races once threads start.
      class_mutex
      tick_gate
    end

    # One scheduler iteration. The atomic gate guarantees a single concurrent
    # execution across every thread in the process (a leaked thread from a
    # dev-reload restart, a slow backup still launching on the previous tick).
    # The body runs inside the executor so Active Record connections are
    # checked out/in correctly and reloaded code is picked up.
    def tick
      # make_true atomically sets the gate and returns true only if it
      # actually changed — i.e. only the thread that flips false->true runs;
      # any concurrent tick sees it already held and bails out.
      return unless tick_gate.make_true

      begin
        Rails.application.executor.wrap { run_due_backup }
      ensure
        tick_gate.make_false
      end
    rescue StandardError => e
      logger.error("Tick: #{e.class}: #{e.message}")
    end

    # Pure decision: should an automatic backup be handled at `now`? True once
    # the configured time has passed today and the day hasn't been handled yet.
    def due?(now: Time.now.getlocal, config: current_config, last_handled_on: last_handled_date)
      return false unless enabled?(config)

      scheduled = scheduled_time_on(config['schedule_time'], now)
      return false unless scheduled
      return false if now < scheduled

      last_handled_on != now.to_date
    end

    # The local wall-clock time the next automatic backup is due, given the
    # stored "HH:MM". nil when scheduling is off or the value is unparseable.
    # Used by the UI to render "daily at HH:MM".
    def scheduled_time_label(config = current_config)
      return nil unless enabled?(config)

      value = config['schedule_time'].to_s
      parse_hh_mm(value) ? value : nil
    end

    # The date the schedule was last handled, or nil if never (or unreadable).
    def last_handled_date
      Date.iso8601(File.read(state_path).strip)
    rescue Errno::ENOENT, ArgumentError
      nil
    end

    # Re-anchor the once-per-day marker after the schedule is changed, so the
    # next run is the *next* occurrence of the configured time: today if it is
    # still ahead, tomorrow if it has already passed. Setting "03:00" at 09:00
    # therefore waits for tomorrow instead of firing an immediate catch-up,
    # while setting "10:00" at 09:00 still runs today. Called from the settings
    # controller on save.
    def reschedule!(now: Time.now.getlocal, config: current_config)
      scheduled = enabled?(config) && scheduled_time_on(config['schedule_time'], now)

      if scheduled && now >= scheduled
        mark_handled!(now.to_date) # today's window already passed → run tomorrow
      else
        FileUtils.rm_f(state_path) # still ahead (or disabled) → eligible today
      end
    end

    private

    def run_due_backup
      now = Time.now.getlocal
      return unless due?(now:)

      # Stamp the day before doing anything that can fail or block. This is the
      # core of the once-per-day guarantee: even if the backup can't run right
      # now, the day counts as handled and we won't retry every tick.
      today = now.to_date
      mark_handled!(today)
      perform_backup(today)
    rescue BackupRunner::Error => e
      logger.error("Automatic backup failed to start: #{e.message}")
    rescue StandardError => e
      logger.error("Automatic backup: #{e.class}: #{e.message}")
    end

    def perform_backup(today)
      if (reason = BackupRunner.unavailable_reason)
        logger.warn("Automatic backup skipped for #{today}: #{reason}")
        return
      end
      return if BackupRunner.in_progress

      logger.info("Triggering automatic backup for #{today}")
      BackupRunner.start(automatic: true)

      # A manual backup broadcasts from the controller and redirects the
      # clicking user into the in-progress view; an automatic one has neither.
      # Push a status-bar + /backups refresh so anyone already on /backups
      # morphs into the in-progress state. Its auto-reload then tracks the
      # phases and appends the finished backup to the list on its own.
      Orchestration::HeliosOperationBroadcaster.broadcast!
    end

    def mark_handled!(date)
      FileUtils.mkdir_p(File.dirname(state_path))
      File.write(state_path, date.iso8601)
    end

    def state_path
      File.join(Rails.configuration.data_path, 'helios', STATE_FILENAME)
    end

    # Process-wide gate so concurrent/leaked threads can't run ticks in
    # parallel. compute_if_absent is atomic on Concurrent::Map.
    def tick_gate
      BACKUP_SCHEDULER_STORAGE.compute_if_absent(:tick_gate) { Concurrent::AtomicBoolean.new(false) }
    end

    def current_config
      Configuration.current.backup_schedule
    end

    def enabled?(config)
      config.present? && ActiveModel::Type::Boolean.new.cast(config['schedule_enabled'])
    end

    # Build the scheduled instant on `now`'s date in `now`'s timezone.
    def scheduled_time_on(value, now)
      hour, minute = parse_hh_mm(value)
      return nil unless hour

      now.change(hour:, min: minute, sec: 0)
    end

    def parse_hh_mm(value)
      match = value.to_s.match(/\A(\d{1,2}):(\d{2})\z/)
      return nil unless match

      hour = match[1].to_i
      minute = match[2].to_i
      return nil unless hour.between?(0, 23) && minute.between?(0, 59)

      [hour, minute]
    end
  end

  private

  def interval
    TICK_INTERVAL
  end

  def run_once
    self.class.tick
  end
end
