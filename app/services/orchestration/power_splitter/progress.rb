module Orchestration
  module PowerSplitter
    # How far the power-splitter has come while (re)calculating historical
    # values. Returns a Snapshot while that phase is running, nil otherwise.
    #
    # IMPORTANT: this couples HELIOS to the power-splitter's log format
    # (power-splitter/lib/loop.rb). While reprocessing history it prints
    #
    #   --- Processing historical data since 2024-05-01
    #   2026-07-29 10:00:02 +0200 - Processing day 2024-05-01
    #     Pushing 288 records to InfluxDB
    #   … one block per day …
    #   --- Processing historical data successfully finished
    #   Starting endless loop for processing current data...
    #
    # and once per interval afterwards a block ending in "Sleeping for …".
    # The share of days between the start day and today gives the percentage.
    # If those strings change, the progress display silently disappears; the
    # recalculation itself is unaffected. The specs pin the patterns.
    class Progress
      # percent is nil while the start day is unknown — the UI then shows that
      # a recalculation is running, just without a percentage.
      Snapshot = Data.define(:day, :percent)

      SINCE_PATTERN = /Processing historical data since (\d{4}-\d{2}-\d{2})/
      DAY_PATTERN = /Processing day (\d{4}-\d{2}-\d{2})/
      # Lines that can only appear once the historical phase is over.
      IDLE_PATTERN = /successfully finished|Starting endless loop|Sleeping for/
      TIMESTAMP_PATTERN = /\A(\d{4}-\d{2}-\d{2}T\S+Z) /

      # One day produces three lines, so this window covers roughly the last
      # 100 processed days — enough to spot the phase, and small enough to be
      # read every few seconds.
      TAIL_LINES = 300

      # Between the signal and the first line of the new run the log still
      # shows the previous (finished) state. Within this window the UI keeps
      # showing "running" so the badge doesn't blink out right after the click.
      TRIGGER_GRACE = 2.minutes

      # Reading the log forks `docker logs`, while the row re-renders on every
      # /services visit, tab refocus and Docker event for the service — and
      # outside a recalculation the answer is always "nothing running". So an
      # idle result is remembered briefly. Only that case is cached: while a
      # run is in flight every render reads afresh, keeping the badge live.
      # A run started outside HELIOS (a shell signal, the initial backfill of
      # a fresh install) thus shows up this much later, which is nothing next
      # to a runtime of minutes to hours.
      IDLE_RECHECK = 30.seconds

      def self.call(container)
        return nil unless container&.running?
        return nil if State.idle?(container.id, within: IDLE_RECHECK)

        snapshot = new(container).call
        State.mark_idle(container.id) unless snapshot
        snapshot
      end

      def initialize(container)
        @container = container
      end

      # Entered through .call, which has already established a running
      # container.
      def call
        running_snapshot || starting_snapshot
      end

      private

      attr_reader :container

      def running_snapshot
        return nil if lines_after_since.any? { |line| line.match?(IDLE_PATTERN) }

        day = last_match(lines_after_since, DAY_PATTERN)
        day && snapshot_for(Date.parse(day))
      end

      # Nothing in the log (yet) confirms a run, but the user just asked for
      # one. Suppressed as soon as the log proves the run has already ended.
      def starting_snapshot
        triggered_at = State.triggered_at
        return nil unless triggered_at && triggered_at > TRIGGER_GRACE.ago
        return nil if last_idle_at && last_idle_at > triggered_at

        Snapshot.new(day: nil, percent: nil)
      end

      # Without a plausible start day the percentage stays unknown; the badge
      # then shows the day alone.
      def snapshot_for(day)
        start_day = since
        return Snapshot.new(day:, percent: nil) unless start_day && start_day <= day && start_day <= Date.current

        done = (day - start_day).to_i + 1
        total = (Date.current - start_day).to_i + 1
        Snapshot.new(day:, percent: ((done * 100.0) / total).round.clamp(0, 100))
      end

      # Everything after the newest "since" line, which is where the current
      # run starts. Once that line has scrolled out, the whole window belongs
      # to the run (a finished run always leaves an IDLE_PATTERN line behind).
      def lines_after_since
        @lines_after_since ||= since_index ? lines[(since_index + 1)..] : lines
      end

      # nil is the normal answer — the window holds ~100 days, so a longer run
      # has scrolled its start line out. Memoized with defined? so that case is
      # not rescanned by each of the three readers.
      def since_index
        return @since_index if defined?(@since_index)

        @since_index = lines.rindex { |line| line.match?(SINCE_PATTERN) }
      end

      # From the log while that line is still in the window, from the
      # configuration afterwards: a recalculation always reprocesses every day
      # since INSTALLATION_DATE, which HELIOS exports to the splitter itself.
      def since
        day = since_index && lines[since_index][SINCE_PATTERN, 1]
        day ? Date.parse(day) : installation_date
      end

      def installation_date
        Date.parse(Configuration.current.system.installation_date.to_s)
      rescue Date::Error
        nil
      end

      def last_idle_at
        line = lines.rfind { |l| l.match?(IDLE_PATTERN) }
        timestamp = line && line[TIMESTAMP_PATTERN, 1]
        timestamp && Time.zone.parse(timestamp)
      end

      # Capture group 1 of `pattern` in the last line matching it.
      def last_match(list, pattern)
        line = list.rfind { |l| l.match?(pattern) }
        line && line[pattern, 1]
      end

      def lines
        @lines ||= DockerCli.log_tail(container.name, lines: TAIL_LINES, timestamps: true).lines
      end
    end
  end
end
