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
  #      both the restored table count and that the configured password still
  #      logs in.
  #   3. finish! — reconcile the stack against the rewritten compose (recreate
  #      dependents, prune the pre-upgrade orphan) and remove the dump file.
  #
  # Recovery: the verified dump file is the safety anchor, written before
  # any destructive step. If the upgrade fails, #rollback! automatically
  # returns to the previous major. A failure before the data directory is
  # touched only reverts the image; once the directory has been wiped, the
  # cluster is rebuilt from that same dump — either way leaving a working
  # stack on the old version. Only if the rollback itself fails is the dump
  # kept on disk and the user pointed to it.
  #
  # On top of that, #ensure_running! guarantees that an abort never leaves the
  # stack without a database as long as the original cluster is intact. Even a
  # read-only phase can end with PostgreSQL down: the dump fails precisely
  # because the container went away while it ran.
  #
  # All of that covers an upgrade that *fails*. An upgrade that is *killed*
  # (HELIOS restarted, host rebooted, container OOM-killed) never reaches any
  # of it — the whole job lives in the HELIOS process. That is what the Journal
  # is for: every step that changes something is recorded on disk first, so the
  # next boot can tell how far the upgrade got and finish or undo it (see
  # #recover!, wired up from config/puma.rb). Automatic updates are paused for
  # the duration on top (see UpdatePause), which removes the most likely cause
  # of such a kill in the first place.
  #
  # The dump never passes through Ruby's heap: pg_dumpall is streamed to the
  # file and psql reads it back streamed from the file, so the upgrade is
  # not bounded by available memory.
  #
  # The whole operation runs through `docker compose exec`/`run` and never
  # touches the PostgreSQL data directory from the host — so it works
  # regardless of whether PostgreSQL uses a bind mount, a custom path, or a
  # named volume.
  class PostgresqlUpgrade # rubocop:disable Metrics/ClassLength
    include Loggable

    SERVICE = 'postgresql'.freeze
    # SOLECTRUS' own database — the one holding the tables worth verifying.
    # Not `solectrus`, which the postgres image creates from POSTGRES_DB and
    # which stays empty (see restore.sh for the same distinction).
    DATABASE = 'solectrus_production'.freeze
    READY_TIMEOUT = 180 # seconds to wait for the upgraded server
    POLL_INTERVAL = 1   # a `pg_isready` probe is cheap; poll responsively
    TABLE_COUNT_SQL =
      "SELECT count(*) FROM pg_tables WHERE schemaname = 'public'".freeze
    # pg_dumpall prints this as its final line; its absence means the dump
    # was truncated and must not be trusted.
    DUMP_COMPLETE_MARKER = 'PostgreSQL database cluster dump complete'.freeze
    # Logs in exactly the way the other services do: over TCP, against the
    # container's own Docker address, with POSTGRES_PASSWORD. The address has
    # to be the container's own rather than 127.0.0.1, since only the former
    # matches the `host all all all scram-sha-256` rule the image appends to
    # pg_hba.conf. Password and address are resolved inside the container, so
    # neither ends up in an argument list, a process listing or a log.
    AUTH_PROBE = <<~SH.freeze
      [ -n "$POSTGRES_PASSWORD" ] || exit 0
      PGPASSWORD="$POSTGRES_PASSWORD" psql -h "$(hostname)" -U postgres -d postgres -tAc 'SELECT 1' > /dev/null
    SH

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

    # True when a previous run was killed before it could finish or undo
    # itself. Drives the recovery at boot; also blocks a fresh upgrade, since
    # the stack is not in a state to start one from.
    def self.interrupted?
      Journal.load.present?
    end

    def self.recover!
      new.recover!
    end

    # Raises UpgradeError with a user-facing message on any failure;
    # returns true on success.
    def call
      raise UpgradeError, t('recovery_pending') if self.class.interrupted?

      prepare!
      migrate!
      finish!
      true
    rescue UpgradeError
      ensure_running!
      raise
    rescue StandardError => e
      ensure_running!
      raise UpgradeError, "#{e.class}: #{e.message}"
    end

    # --- Recovery after an interrupted run ---

    # Picks up where a killed upgrade left off. Returns false when there is
    # nothing to recover (the normal case) and true when the upgrade was
    # carried to its end. It raises UpgradeError with the message the user has
    # to see whenever the outcome is not simply "upgraded": an upgrade that had
    # to be undone reports just like a failed one does, since in both cases the
    # user clicked Upgrade and did not get one.
    #
    # What "a defined state" means depends on how far the upgrade got:
    #
    #   preparing   nothing was changed — drop the half-written dump
    #   migrating   only the configured image was bumped, the old cluster is
    #               untouched — revert to the previous major
    #   rebuilding  the data directory was emptied, the dump is the only copy
    #               of the data — rebuild the cluster from it, exactly as the
    #               upgrade itself would have. A failure here falls through to
    #               the normal rollback, which rebuilds the *old* major from
    #               the same dump
    #   finishing   the data is already migrated and verified — only the stack
    #               reconcile is left
    def recover!
      interrupted = Journal.load
      return false if interrupted.nil?

      adopt!(interrupted)
      logger.warn("resuming an upgrade interrupted in phase #{journal.phase}")
      recover_from(journal.phase)
      logger.info("recovery from phase #{journal.phase} completed")
      true
    rescue UpgradeError
      raise
    rescue StandardError => e
      raise UpgradeError, "#{e.class}: #{e.message}"
    end

    private

    attr_reader :journal

    def recover_from(phase)
      case phase
      when :preparing then abandon_upgrade!
      when :migrating then revert_upgrade!
      when :rebuilding then resume_rebuild!
      when :finishing then finish!
      end
    end

    # Restores the state the interrupted run held in memory, so the recovery
    # steps can reuse the very code paths the upgrade itself uses.
    def adopt!(interrupted)
      @journal = interrupted
      @dump_path = interrupted.dump_path
      @previous_image = interrupted.previous_image
      @previous_pgdata = interrupted.previous_pgdata
      @previous_major = interrupted.previous_major
      @expected_tables = interrupted.expected_tables
    end

    # Phase :preparing — the dump was still being written, so nothing outside
    # HELIOS' own data directory was touched. Only the partial dump has to go.
    def abandon_upgrade!
      cleanup_dump
      journal.clear!
      ensure_running!

      raise UpgradeError, t('recovery_aborted')
    end

    # Phase :migrating — the new image is configured but the old cluster is
    # still on disk, untouched. Reverting the configuration is all it takes;
    # leaving it would have PostgreSQL refuse to start on the next recreate
    # (a new major does not read an old major's data directory).
    def revert_upgrade!
      write_postgresql_config(image: @previous_image, pgdata: @previous_pgdata)
      rebuild_stack!
      Runner.start(SERVICE)
      AffectedServices.update_deployed_hash!(SERVICE)
      cleanup_dump
      journal.clear!

      raise UpgradeError, t('recovery_reverted', major: @previous_major)
    end

    # Phase :rebuilding — the data directory was emptied, so the dump is the
    # only complete copy of the data. Finish the upgrade from it; a failure
    # hands over to the normal rollback, which rebuilds the previous major
    # from the same dump.
    #
    # Without the dump there is nothing left to rebuild from: the journal is
    # dropped (retrying it every boot would not change the outcome) and the
    # user is pointed at a backup.
    def resume_rebuild!
      unless dump_available?
        journal.clear!
        raise UpgradeError, t('recovery_impossible', path: dump_path)
      end

      @data_directory_touched = true
      begin
        rebuild_cluster_from_dump!
        verify_restore!
        verify_authentication!
      rescue StandardError => e
        rollback!(e)
      end
      journal.advance!(:finishing)
      finish!
    end

    # A dump that is missing entirely raises out of dump_complete? and lands
    # in the same "cannot be rebuilt from" answer as a truncated one.
    def dump_available?
      dump_complete?
    rescue SystemCallError
      false
    end

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
      # Opened before the dump, not after: a dump killed halfway leaves a
      # partial file behind that nothing else would ever clean up.
      @journal = Journal.start!(
        dump_path:,
        previous_image: @previous_image,
        previous_pgdata: @previous_pgdata,
        previous_major: @previous_major,
        expected_tables: @expected_tables,
      )
      create_dump!
    end

    # The phase that mutates the stack. Any failure hands off to #rollback!,
    # which always raises an UpgradeError describing the outcome.
    def migrate!
      journal.advance!(:migrating)
      bump_image!
      rebuild_cluster_from_dump!
      verify_restore!
      verify_authentication!
      journal.advance!(:finishing)
    rescue StandardError => e
      rollback!(e)
    end

    def finish!
      reconcile_stack!
      cleanup_dump
      journal&.clear!
    end

    # Brings PostgreSQL back up after an abort that left the original cluster
    # intact. #prepare! is read-only, so an abort there is meant to leave a
    # running service behind — but the dump can fail precisely because the
    # container went away while it ran, and then nothing would start it again:
    # the stack would sit without a database until someone notices (the next
    # backup refusing to run, for instance).
    #
    # Skipped once the data directory has been wiped: there the dump is still
    # the only complete copy, and a half-rebuilt cluster must not come up and
    # let the dashboard write into it. #rollback! owns that case.
    def ensure_running!
      return if @data_directory_touched
      return if running?

      logger.warn("#{SERVICE} is down after a failed upgrade, starting it again")
      Runner.start(SERVICE)
    rescue StandardError => e
      logger.error("failed to start #{SERVICE} after a failed upgrade: #{e.class}: #{e.message}")
    end

    def running?
      Container.invalidate_cache
      Container.find(SERVICE)&.running? || false
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
    #
    # --no-role-passwords keeps the dump from carrying the superuser's password
    # hash across majors. PostgreSQL 13 and older store it MD5-encrypted, while
    # the image's pg_hba.conf demands scram-sha-256 from 14 on — and SCRAM
    # cannot fall back to an MD5 secret (only the reverse works). Restoring the
    # hash would overwrite the SCRAM secret initdb just derived from
    # POSTGRES_PASSWORD and leave a cluster no service can log in to. Without
    # the passwords the dump only recreates the roles themselves, and the
    # password the new cluster was initialized with stays in place — correctly
    # encrypted for whichever major is being built, so a rollback to the old
    # one works just the same.
    def create_dump!
      stderr, code =
        Runner.compose_exec_streaming(
          SERVICE, 'pg_dumpall', '-U', 'postgres', '--no-role-passwords', out_path: dump_path
        )

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
      # Recorded before the data directory is touched: from here on, a killed
      # HELIOS leaves a cluster that only the dump can rebuild, and the next
      # boot must not let PostgreSQL come up on the empty directory instead.
      journal.advance!(:rebuilding)
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
        journal.clear!
        raise UpgradeError, t('rolled_back', detail:, major: @previous_major)
      end

      # The journal survives a failed rollback on purpose: the cluster is not
      # in a usable state, and rebuilding it from the preserved dump is worth
      # another attempt on the next boot.

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

      AffectedServices.update_deployed_hash!(SERVICE)
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

    # Guards against a cluster that is up and holds all its data, but that no
    # service can log in to. Every other check runs over a connection the
    # image's pg_hba.conf trusts unconditionally — HELIOS' own psql calls go
    # through the Unix socket, #accepting_tcp_connections? probes 127.0.0.1 —
    # so a broken password would pass verification and surface much later, as
    # a dashboard that cannot reach its database.
    #
    # Skipped when the container has no POSTGRES_PASSWORD (see AUTH_PROBE):
    # there is nothing to probe with then, and failing an otherwise complete
    # upgrade over it would do more harm than not checking.
    def verify_authentication!
      _stdout, stderr, code = Runner.compose_exec(SERVICE, 'sh', '-c', AUTH_PROBE)
      return if code&.zero?

      raise UpgradeError, t('auth_failed', detail: last_line(stderr))
    end

    # Brings the affected services in line with the rewritten compose (see
    # #reconcile_services for which those are). Recreating only `postgresql`
    # would leave dependents running against the old database (the dashboard
    # embeds the host in DB_HOST, which changes when an imported `db` service
    # becomes the canonical `postgresql`) and leave the pre-rename container
    # behind as a crash-looping orphan. Each reconciled service is baselined
    # afterwards so its stale "restart required" marker clears. A reconcile
    # failure is not an upgrade failure (the data is already migrated) so it must
    # not roll back — it is reported with a message pointing the user at a
    # manual restart.
    def reconcile_stack!
      services = reconcile_services
      Runner.reconcile(services)
      services.each { |service| AffectedServices.update_deployed_hash!(service) }
    rescue Runner::CommandError => e
      raise UpgradeError, t('reconcile_failed', detail: last_line(e.stdout))
    end

    # PostgreSQL itself plus the running services that depend on it — exactly
    # those the upgrade affects: their database container was replaced, and in
    # an imported stack their DB_HOST changed with the rename to `postgresql`.
    #
    # Deliberately not every running service: an imported stack that was never
    # redeployed drifts in every service, and sweeping that along would recreate
    # containers the user never asked about — discarding their logs, which are
    # the only trace left when something goes wrong. Excludes HELIOS itself;
    # orphans (service gone from compose) are pruned project-wide by
    # Runner.reconcile's --remove-orphans, not by being listed here.
    def reconcile_services
      compose_services = ::Compose.load.services
      running = Container.all.select(&:running?).filter_map(&:service_name).uniq

      dependents =
        running.select { |name| compose_services.find(name)&.depends_on&.include?(SERVICE) }

      ([SERVICE] + dependents).uniq - [Runner::SELF_SERVICE]
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
