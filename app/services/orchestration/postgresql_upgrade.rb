module Orchestration
  # Performs a PostgreSQL major-version upgrade by dump & restore — the only
  # supported path across major versions, since the on-disk data format is
  # not forward-compatible (a new major refuses to start on an old major's
  # data directory). Driven by PostgresqlUpgradeJob as one orchestrated
  # background operation.
  #
  # Sequence (see #call):
  #   1. prepare! — read-only. Count the running database's tables and
  #      stream a full `pg_dumpall` straight into a file in HELIOS' own
  #      data_path. The dump is checked for its completion marker before
  #      anything destructive runs.
  #   2. migrate! — destructive. Bump the configured image to the new major,
  #      then rebuild the cluster from the dump: stop PostgreSQL, empty the
  #      data directory, start the new major, restore the dump, and verify
  #      the restored table count.
  #   3. finish! — record the deployment and remove the dump file.
  #
  # Recovery: the verified dump file is the safety anchor, written before
  # any destructive step. If the destructive phase fails, #rollback!
  # automatically returns to the previous major — it reverts the image and
  # rebuilds the cluster from that same dump, leaving a working stack on the
  # old version. Only if the rollback itself fails is the dump kept on disk
  # and the user pointed to it.
  #
  # The dump never passes through Ruby's heap: pg_dumpall is streamed to the
  # file and psql reads it back streamed from the file, so the upgrade is
  # not bounded by available memory.
  #
  # The whole operation runs through `docker compose exec`/`run` and never
  # touches the PostgreSQL data directory from the host — so it works
  # regardless of whether PostgreSQL uses a bind mount, a custom path, or a
  # named volume.
  class PostgresqlUpgrade
    SERVICE = 'postgresql'.freeze
    DATABASE = 'solectrus'.freeze
    READY_TIMEOUT = 180 # seconds to wait for the upgraded server
    POLL_INTERVAL = 1   # health is a cheap `docker inspect`; poll responsively
    TABLE_COUNT_SQL =
      "SELECT count(*) FROM pg_tables WHERE schemaname = 'public'".freeze
    # pg_dumpall prints this as its final line; its absence means the dump
    # was truncated and must not be trusted.
    DUMP_COMPLETE_MARKER = 'PostgreSQL database cluster dump complete'.freeze

    class UpgradeError < StandardError
    end

    # --- Detection (used by the UI) ---

    def self.target_image
      DockerImages.current(:POSTGRESQL)
    end

    def self.target_major
      DockerImages.postgresql_major(target_image)
    end

    # Major version of the running server, read from the container's
    # PG_VERSION (e.g. "17.5" → 17).
    def self.current_major(container)
      container&.version.to_s[/\d+/]&.to_i
    end

    # True when a one-click major upgrade is possible: PostgreSQL is running
    # an older major than the recommended image.
    def self.available?(container)
      return false unless container&.running?

      current = current_major(container)
      target = target_major
      current.present? && target.present? && current < target
    end

    def self.call
      new.call
    end

    # Raises UpgradeError with a user-facing message on any failure;
    # returns true on success.
    def call
      prepare!
      migrate!
      finish!
      true
    rescue UpgradeError
      raise
    rescue StandardError => e
      raise UpgradeError, "#{e.class}: #{e.message}"
    end

    private

    # --- Phases ---

    # Read-only: nothing here mutates the stack. Captures the dump that the
    # destructive phase — and any rollback — relies on.
    def prepare!
      container = Container.find(SERVICE)
      raise UpgradeError, t('not_upgradable') unless self.class.available?(container)

      @previous_image = Configuration.current.postgresql.image
      @previous_major = self.class.current_major(container)
      @expected_tables = count_tables
      create_dump!
    end

    # Destructive. Any failure hands off to #rollback!, which always raises
    # an UpgradeError describing the outcome.
    def migrate!
      bump_image!
      rebuild_cluster_from_dump!
      verify_restore!
    rescue StandardError => e
      rollback!(e)
    end

    def finish!
      mark_deployed!
      cleanup_dump
    end

    # --- Steps ---

    def count_tables
      stdout, _stderr, code =
        Runner.compose_exec(
          SERVICE, 'psql', '-U', 'postgres', '-d', DATABASE, '-tAc', TABLE_COUNT_SQL
        )
      code&.zero? ? stdout.strip.to_i : nil
    end

    # Streams pg_dumpall straight to a file in HELIOS' own data_path while
    # the old server still runs — never buffering the dump in memory. A
    # truncated dump is rejected (and removed) before the destructive phase
    # begins.
    def create_dump!
      stderr, code =
        Runner.compose_exec_streaming(SERVICE, 'pg_dumpall', '-U', 'postgres', out_path: dump_path)

      unless code&.zero?
        cleanup_dump
        raise UpgradeError, t('dump_failed', detail: last_line(stderr))
      end
      return if dump_complete?

      cleanup_dump
      raise UpgradeError, t('dump_incomplete')
    end

    def bump_image!
      update_postgresql_image(self.class.target_image)
      rebuild_stack!
      Runner.pull(service: SERVICE)
    end

    # Builds a fresh cluster for the currently configured image and loads
    # the dump into it. Used by both the forward migration and the rollback,
    # which differ only in which image is configured beforehand. Starts by
    # stopping PostgreSQL so the data directory can be emptied safely.
    def rebuild_cluster_from_dump!
      Runner.stop(SERVICE)
      wipe_data_directory!
      Runner.start(SERVICE)
      wait_until_ready!
      restore_dump!
    end

    # Best-effort return to the previous major after a failed upgrade.
    # Reverts the image and rebuilds the cluster from the dump captured in
    # #prepare!, so the stack ends up running on the old version with the
    # original data. Always raises an UpgradeError: either reporting the
    # completed rollback, or — if the rollback itself failed — pointing the
    # user to the preserved dump.
    def rollback!(original_error)
      detail = error_detail(original_error)

      if perform_rollback
        cleanup_dump
        raise UpgradeError, t('rolled_back', detail:, major: @previous_major)
      end

      raise UpgradeError,
            t(
              'rollback_failed',
              detail:,
              error: error_detail(@rollback_error),
              path: dump_path,
            )
    end

    def perform_rollback
      update_postgresql_image(@previous_image)
      rebuild_stack!
      rebuild_cluster_from_dump!
      mark_deployed!
      true
    rescue StandardError => e
      Rails.logger.error("PostgresqlUpgrade rollback failed: #{e.class}: #{e.message}")
      @rollback_error = e
      false
    end

    # initdb refuses a non-empty data directory, so a fresh cluster needs a
    # clean one. Emptied from inside a throwaway container — works for any
    # volume type, unlike a host-side rename. The mount target depends on
    # the configured major (see DockerImages.postgresql_data_path).
    def wipe_data_directory!
      major = DockerImages.postgresql_major(Configuration.current.postgresql.image)
      mount = DockerImages.postgresql_data_path(major)
      _stdout, stderr, code =
        Runner.compose_run(SERVICE, '-c', "find #{mount} -mindepth 1 -delete",
                           entrypoint: 'sh')
      return if code&.zero?

      raise UpgradeError, t('wipe_failed', detail: last_line(stderr))
    end

    def wait_until_ready!
      deadline = Time.current + READY_TIMEOUT

      loop do
        Container.invalidate_cache
        return if Container.find(SERVICE)&.healthy?
        raise UpgradeError, t('not_ready') if Time.current > deadline

        sleep POLL_INTERVAL
      end
    end

    # Streams the dump from the file into psql — the file is never read into
    # memory.
    def restore_dump!
      stderr, code =
        Runner.compose_exec_streaming(SERVICE, 'psql', '-U', 'postgres', in_path: dump_path)
      return if code&.zero?

      raise UpgradeError, t('restore_failed', detail: last_line(stderr))
    end

    # Structural sanity check: the restored database must hold the same
    # number of public tables as the original. Skipped when the pre-dump
    # count could not be determined.
    def verify_restore!
      return if @expected_tables.nil?

      actual = count_tables
      return if actual == @expected_tables

      raise UpgradeError,
            t('verify_failed', expected: @expected_tables, actual: actual || '?')
    end

    # --- Helpers ---

    # pg_dumpall ends with the completion marker as its final line; its
    # absence means the dump was truncated. Checked by reading only the
    # file's tail, so the dump itself is never loaded into memory.
    def dump_complete?
      tail =
        File.open(dump_path) do |file|
          file.seek(-[200, file.size].min, IO::SEEK_END)
          file.read
        end
      tail.to_s.include?(DUMP_COMPLETE_MARKER)
    end

    # Removes the dump file once it is no longer needed — on a clean upgrade,
    # after a successful rollback, or when a failed dump left a partial file.
    # Best-effort: rm_f neither raises on a missing file nor on errors.
    def cleanup_dump
      FileUtils.rm_f(dump_path)
    end

    def dump_path
      @dump_path ||=
        File.join(data_path, "postgresql-upgrade-#{Time.current.strftime('%Y%m%d%H%M%S')}.sql")
    end

    def mark_deployed!
      AffectedServices.update_deployed_hash!(SERVICE)
    end

    def update_postgresql_image(image)
      config = Configuration.current
      config.update('postgresql', config.postgresql.merge('image' => image))
    end

    def rebuild_stack!
      Export::Builder.new(Configuration.current).write!
    end

    def data_path
      Rails.configuration.data_path
    end

    def error_detail(error)
      return 'Unknown error' if error.nil?

      error.is_a?(UpgradeError) ? error.message : "#{error.class}: #{error.message}"
    end

    def last_line(text)
      text.to_s.lines.last&.strip.presence || 'Unknown error'
    end

    def t(key, **)
      I18n.t("orchestration.postgresql_upgrade.#{key}", **)
    end
  end
end
