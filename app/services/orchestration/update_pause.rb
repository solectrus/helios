module Orchestration
  # Keeps Watchtower from recreating containers while a long-running,
  # interruption-sensitive operation is in flight: a CSV import, a backup, a
  # restore or a PostgreSQL major upgrade.
  #
  # An automatic update *recreates* the container it updates. InfluxDB going
  # away halfway through an import loses the rest of the import; PostgreSQL
  # recreated between the dump and the restore of a major upgrade loses the
  # cluster. HELIOS itself surviving such a restart is already covered (the
  # sidecars are detached, their state lives in files), the neighbouring
  # services are not.
  #
  # The pause is the blunt but complete variant: Watchtower is frozen for the
  # duration (`docker compose pause`), so *no* container can be updated,
  # whatever the operation happens to touch. Nothing in compose.yaml/.env
  # changes, which is what makes it work for adopted stacks that were never
  # redeployed.
  #
  # Docker's own pause, not a stop: the container keeps its identity, its logs
  # and its place in the stack, comes back in a fraction of a second, and says
  # so itself — `paused` is a state Docker reports, so the UI renders it
  # through the ordinary status path instead of a special case.
  #
  # Crash safety is the whole design problem here — an update pause that leaks
  # means a stack that never sees another update, silently. So whether the
  # pause may end is never read from the marker file: it is derived from live
  # Docker state (#operation_in_flight?), which a HELIOS crash cannot falsify.
  # The marker only records that *HELIOS* took Watchtower down, so a service
  # the user stopped themselves is never brought back. BackupScheduler sweeps
  # on every tick (it is the one thread reliably awake), and MAX_AGE is the
  # last-resort valve for the case where liveness cannot be determined at all.
  #
  # Ending the pause therefore belongs to the sweep, not to the operations:
  # while a runner's own completion callback runs, its thread is still alive
  # and the operation still counts as in flight. An operation that finishes
  # inside the HELIOS process (the PostgreSQL upgrade) is the exception — it
  # resumes directly from its own ensure.
  class UpdatePause
    extend Loggable

    SERVICE = 'watchtower'.freeze
    STATE_FILENAME = 'watchtower_pause.json'.freeze

    # How long a pause may persist before it is lifted regardless of what the
    # liveness check says. Only reachable when that check is broken (Docker
    # unreachable for hours, a sidecar wedged forever) — a real CSV import of
    # this length would be pathological.
    MAX_AGE = 12.hours

    class << self
      # No-op when Watchtower is not running: either automatic updates are off,
      # or the user stopped the service themselves. Both must survive the
      # operation untouched, hence no marker and nothing to resume.
      def pause!(reason)
        return if paused?
        return unless watchtower_running?

        # Written before the pause, not after: `docker pause` fires an event
        # that has StackStatus recompute within milliseconds, and a marker that
        # is not there yet would have Watchtower counted as a plain stopped
        # service — turning the whole stack amber for the duration.
        write_marker!(reason)
        Runner.pause(SERVICE)
        logger.info("automatic updates paused (#{reason})")
      rescue StandardError => e
        # Guarding an operation must never be able to prevent it. Which of the
        # two failures happened decides what to do with the marker written a
        # moment ago: the pause never took effect (drop it, or the next sweep
        # would report a resume nobody asked for), or it did and the command
        # still reported an error (keep it, or nothing would ever thaw
        # Watchtower again). Only live state can tell them apart, and when it
        # cannot be read at all the marker stays — a stale one costs a single
        # sweep, a missing one costs every future update.
        clear_marker! unless watchtower_paused_or_unknown?
        logger.error("pausing automatic updates failed: #{e.class}: #{e.message}")
      end

      def resume_if_idle!
        marker = read_marker
        return if marker.nil?
        return if operation_in_flight? && !stale?(marker)

        Runner.unpause(SERVICE) if watchtower_paused?
        clear_marker!
        logger.info('automatic updates resumed')
      rescue StandardError => e
        logger.error("resuming automatic updates failed: #{e.class}: #{e.message}")
      end

      def paused?
        read_marker.present?
      end

      private

      # Deliberately derived from Docker instead of from in-process
      # bookkeeping: a HELIOS restart wipes every trace of a running operation,
      # while the detached sidecar that outlives it stays visible.
      #
      # Ordered cheapest first: this runs on every scheduler tick for the whole
      # duration of a pause, and only CsvImportRunner.in_progress? forks a
      # `docker inspect` (the others read an in-memory map or a short-lived
      # cache). A backup, restore or upgrade therefore answers without one.
      def operation_in_flight?
        PendingOperations.get(PostgresqlUpgrade::SERVICE) == :upgrade ||
          BackupRunner.in_progress.present? ||
          RestoreRunner.in_progress.present? ||
          CsvImportRunner.in_progress?
      rescue StandardError => e
        # Unable to tell — assume an operation is running, since resuming
        # during one is the expensive mistake. MAX_AGE breaks the tie.
        logger.error("in-flight check failed: #{e.class}: #{e.message}")
        true
      end

      def watchtower_running?
        Container.invalidate_cache
        Container.find(SERVICE)&.running? || false
      end

      # `docker compose unpause` errors on a container that is not paused, and
      # that error would keep the marker alive for every following sweep. So
      # the state is checked rather than the error rescued: a Watchtower the
      # user recreated meanwhile is simply left alone, while a genuine Docker
      # failure still preserves the marker for the next attempt.
      def watchtower_paused?
        Container.invalidate_cache
        Container.find(SERVICE)&.status == 'paused'
      end

      # Same question asked from inside a rescue, where the Docker call that
      # answers it may be exactly what just failed: an unreadable state must
      # not raise a second time, and it counts as "possibly paused".
      def watchtower_paused_or_unknown?
        watchtower_paused?
      rescue StandardError
        true
      end

      def stale?(marker)
        paused_at = Time.zone.parse(marker['paused_at'].to_s)
        return true if paused_at.nil?
        return false if paused_at > MAX_AGE.ago

        logger.warn("automatic updates paused since #{paused_at}, resuming despite a running operation")
        true
      end

      def read_marker
        JSON.parse(File.read(state_path))
      rescue Errno::ENOENT, JSON::ParserError
        nil
      end

      # The reason is recorded for diagnosis only (it also goes to the log) —
      # the UI states that updates are paused, not what for.
      def write_marker!(reason)
        FileUtils.mkdir_p(File.dirname(state_path))
        File.write(
          state_path,
          JSON.generate(reason: reason.to_s, paused_at: Time.current.iso8601),
        )
      end

      def clear_marker!
        FileUtils.rm_f(state_path)
      end

      def state_path
        File.join(Rails.configuration.data_path, 'helios', STATE_FILENAME)
      end
    end
  end
end
