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
  # any destructive step. If the upgrade fails, #rollback! automatically
  # returns to the previous major. A failure before the data directory is
  # touched only reverts the image; once the directory has been wiped, the
  # cluster is rebuilt from that same dump — either way leaving a working
  # stack on the old version. Only if the rollback itself fails is the dump
  # kept on disk and the user pointed to it.
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
    include Loggable

    SERVICE = 'postgresql'.freeze
    DATABASE = 'solectrus'.freeze
    READY_TIMEOUT = 180 # seconds to wait for the upgraded server
    POLL_INTERVAL = 1   # a `pg_isready` probe is cheap; poll responsively
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
      @previous_pgdata = Configuration.current.postgresql.pgdata
      @previous_major = self.class.current_major(container)
      @expected_tables = count_tables
      create_dump!
    end

    # The phase that mutates the stack. Any failure hands off to #rollback!,
    # which always raises an UpgradeError describing the outcome.
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

    # Drops any stale PGDATA: the upgrade builds a brand-new cluster, so the
    # new major can use the image's own per-major default location instead of
    # a path inherited from the old major.
    def bump_image!
      write_postgresql_config(image: self.class.target_image, pgdata: nil)
      rebuild_stack!
      Runner.pull(service: SERVICE)
    end

    # Builds a fresh cluster for the currently configured image and loads
    # the dump into it. Used by both the forward migration and the rollback,
    # which differ only in which image is configured beforehand. Starts by
    # stopping PostgreSQL so the data directory can be emptied safely.
    def rebuild_cluster_from_dump!
      Runner.stop(SERVICE)
      # From here on the data directory is gone — a failure can only be
      # recovered by rebuilding the cluster, never by reverting files.
      @data_directory_touched = true
      wipe_data_directory!
      Runner.start(SERVICE)
      wait_until_ready!
      restore_dump!
    end

    # Best-effort return to the previous major after a failed upgrade (see
    # #perform_rollback), so the stack ends up running on the old version
    # with the original data. Always raises an UpgradeError: either reporting
    # the completed rollback, or — if the rollback itself failed — pointing
    # the user to the preserved dump.
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

    # Reverts the image (and PGDATA) to the previous major. When the data
    # directory was never touched — the upgrade failed before its first
    # destructive step — the old cluster is still intact and only the compose
    # files need reverting. Once the directory has been wiped, the cluster has
    # to be rebuilt from the dump.
    def perform_rollback
      write_postgresql_config(image: @previous_image, pgdata: @previous_pgdata)
      rebuild_stack!

      if @data_directory_touched
        rebuild_cluster_from_dump!
      else
        Runner.start(SERVICE)
      end

      mark_deployed!
      true
    rescue StandardError => e
      logger.error("rollback failed: #{e.class}: #{e.message}")
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

    # Waits until the freshly started server accepts TCP connections.
    #
    # Probed over TCP rather than via the container's healthcheck on purpose:
    # on a first-time start the postgres image runs a temporary bootstrap
    # server that listens on the Unix socket only (`listen_addresses=''`). The
    # socket-based healthcheck can flip to "healthy" against that throwaway
    # server; a TCP probe stays negative until the real server is up, so the
    # restore never races the bootstrap.
    def wait_until_ready!
      deadline = Time.current + READY_TIMEOUT

      loop do
        return if accepting_tcp_connections?
        raise UpgradeError, t('not_ready') if Time.current > deadline

        sleep POLL_INTERVAL
      end
    end

    def accepting_tcp_connections?
      _stdout, _stderr, code =
        Runner.compose_exec(SERVICE, 'pg_isready', '-h', '127.0.0.1', '-U', 'postgres', '-q')
      code&.zero?
    end

    # Streams the dump from the file into psql — the file is never read into
    # memory.
    #
    # psql runs lenient (no ON_ERROR_STOP): a pg_dumpall script always begins
    # with statements that error harmlessly on a freshly initialized cluster
    # — `CREATE ROLE postgres` (the bootstrap superuser, undroppable) and
    # `CREATE DATABASE` for the database the postgres image already created
    # from POSTGRES_DB. Stopping on the first error would abort every single
    # restore; gross failures are caught afterwards by #verify_restore!.
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

    # Writes the postgresql section's image and PGDATA. A nil pgdata removes
    # the key entirely, so the section never carries a stale data-directory
    # override after the cluster has been rebuilt.
    def write_postgresql_config(image:, pgdata:)
      config = Configuration.current
      data = config.postgresql.except('pgdata').merge('image' => image)
      data['pgdata'] = pgdata if pgdata.present?
      config.update('postgresql', data)
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
