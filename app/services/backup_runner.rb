# Runs the backup as a detached `docker:cli` container (see DetachedRunner
# for the shared launch / in-progress machinery).
#
# End-to-end flow (the work is split across three actors that share state
# through bind mounts and small marker files):
#
#   1. `start` (this class, Ruby/HELIOS side)
#      - validate!         — env, config, tokens, destination, both DB
#                            services running, no concurrent restore
#      - pull_image_if_needed!  (docker:cli)
#      - preflight_destination! — sidecar probe of an external mount
#                                 *before* the long-running container, so
#                                 NAS-offline / USB-unplugged surfaces as
#                                 a precise red banner on click
#      - prune!            — keep the configured number of backups
#      - run_container!    — `docker run -d` (detached, --rm); the runner
#                            container outlives the HTTP request and
#                            even survives a HELIOS restart
#      - mark_pending!     — record the planned filename for the UI
#      - start S3 uploader thread if destination == 's3'
#
#   2. backup.sh (inside the detached sidecar; positional argv)
#      Phases written atomically to /runtime/backup-phase.txt and read
#      back by `DetachedRunner.current_phase` on every /backups poll:
#        :dumping_postgres → docker exec pg_dump | gzip → /work (the
#                            sidecar's own writable layer, not a bind
#                            mount — the bundling symlink below needs a
#                            filesystem that supports symlink(), which
#                            some bind-mount backends don't; issue #305)
#        :dumping_influx   → docker exec influx backup  → /influx-backup-staging
#                            (shared bind mount with the InfluxDB
#                             container; no docker-exec stdio pipe, no
#                             gzip-on-gzip)
#        :bundling         → symlink staging into /work, then
#                            `tar -h -cf` the whole work dir into
#                            /output/<file>.part; rename to final on
#                            success. Failures land in
#                            /runtime/error.txt (local, never /output —
#                            the destination itself may be the cause).
#      The sidecar writes the tar to /output and exits. /output is:
#        - local destination:    HELIOS's own backups dir
#        - external destination: the user's bind-mounted NAS/USB path
#        - S3 destination:       local S3 staging dir (uploaded next)
#
#   3. BackupRepository::S3::Uploader (HELIOS-side background thread,
#      only when destination == 's3')
#      Waits for the sidecar to exit, uploads the staged tar via
#      aws-sdk-s3, records the DB row, removes the local copy. A HELIOS
#      restart mid-upload (e.g. Watchtower self-update) kills the thread;
#      `in_progress` re-spawns it on the next render so the user does
#      not have to resubmit.
#
# Mutual exclusion: the fixed CONTAINER_NAME doubles as a lock — a second
# `docker run --name` collides and fails. The cross-runner check against
# RestoreRunner (in `validate!`) reads docker live, never the
# IN_PROGRESS_CACHE_TTL cache — a backup and restore launching within
# the same 3 s window must not both observe a stale nil.
class BackupRunner < DetachedRunner
  CONTAINER_NAME = 'helios-backup-runner'.freeze
  IMAGE = 'docker:29-cli'.freeze
  POSTGRES_SERVICE = 'postgresql'.freeze
  INFLUXDB_SERVICE = 'influxdb'.freeze
  PHASE_FILENAME = 'backup-phase.txt'.freeze
  I18N_SCOPE = 'backups.runner'.freeze

  # Phase names the backup script writes into PHASE_FILENAME. Anything
  # outside this allowlist falls back to the generic "In progress…" label.
  # :preparing is *not* a script phase — it is the HELIOS-side image pull +
  # container launch tracked via the preparing thread (see below), so it
  # lives only in the progress component's phase list, never in this marker
  # allowlist.
  KNOWN_PHASES = %i[dumping_postgres dumping_influx bundling].freeze

  SCRIPT_PATH = ::File.join(__dir__, 'backup_runner', 'backup.sh').freeze

  # Read on every start instead of caching into a frozen constant: Rails'
  # autoreloader only watches .rb files, so a constant would pin the script
  # to whatever was on disk at boot — edits would silently no-op until the
  # dev server is restarted. In production the container is spawned fresh
  # per backup anyway, so the file read is noise.
  def self.script
    ::File.read(SCRIPT_PATH)
  end

  class << self
    # Overrides DetachedRunner's plain `delegate :start, to: :new` so the
    # caller can flag a scheduler-triggered run (Issue #106). Automatic runs
    # don't leave a completion card to dismiss on success.
    def start(automatic: false)
      new.start(automatic:)
    end

    # Reason why a fresh backup cannot be started right now, or nil if it can.
    # In-progress states are excluded — the UI surfaces those separately.
    delegate :unavailable_reason, to: :new

    # Whether both database services exist in compose.yaml. When they don't,
    # the Backup tab shows an empty state; when they merely aren't running,
    # the create form stays visible with a disabled button.
    delegate :databases_configured?, to: :new

    # Extends the inherited in_progress with two HELIOS-side phases the base
    # runner doesn't know about: the :preparing phase (image pull + container
    # launch, run in a background thread so the click redirects to the
    # progress page immediately — mirrors CsvImportRunner) and the S3 upload
    # phase (re-spawning the uploader if a HELIOS restart killed the thread
    # while the staged tar is still on disk).
    def in_progress
      preparing_in_progress ||           # HELIOS prep thread, no container yet
        super ||                         # the running docker:cli sidecar (base)
        s3_upload_in_progress_or_resume  # post-exit S3 upload tail
    end

    # True while the background thread is pulling docker:cli + launching the
    # container. Process-local; a HELIOS restart kills it — the next /backups
    # poll then falls through to the (now-running) container, or to the
    # failure card if preparing left an error file behind.
    def preparing?
      mutex.synchronize { @preparing_thread&.alive? || false }
    end

    # Hands the slow pull + launch off to a thread so the controller can
    # redirect to the progress page immediately. Single-flight; mirrors
    # CsvImportRunner.spawn_preparing_thread!. started_at/filename are
    # captured here so the progress page can label the run before any
    # container exists.
    def spawn_preparing_thread!(instance)
      mutex.synchronize do
        return if @preparing_thread&.alive?

        @preparing_started_at = instance.send(:timestamp)
        @preparing_filename = instance.send(:backup_filename)
        @preparing_thread = Thread.new do # rubocop:disable ThreadSafety/NewThread
          Rails.application.executor.wrap { instance.send(:run_preparing!) }
        end
      end
    end

    def s3_upload_in_progress_or_resume
      return nil unless BackupRepository.s3?

      current = BackupRepository::S3::Uploader.current
      return current if current

      filename = BackupRepository.storage.pending_filename
      return nil if filename.blank?
      return nil unless BackupRepository::S3.staged_tar_exists?(filename)

      BackupRepository::S3::Uploader.start_async(filename)
      BackupRepository::S3::Uploader.current
    end

    private

    # An InProgress snapshot for the :preparing phase, or nil when no prep
    # thread is alive.
    def preparing_in_progress
      mutex.synchronize do
        return nil unless @preparing_thread&.alive?

        BackupRepository::InProgress.new(
          started_at: @preparing_started_at,
          filename: @preparing_filename,
          phase: :preparing,
        )
      end
    end

    def mutex
      @mutex ||= Mutex.new # rubocop:disable ThreadSafety/ClassInstanceVariable
    end
  end

  # validate! runs synchronously so its cheap, immediately-fixable failures
  # (env/config/tokens missing, a database service down, a concurrent run)
  # still surface as a red banner on click. Everything that can take a while
  # — notably the docker:cli pull on a fresh host — moves into the preparing
  # thread so the click redirects straight to the progress page (mirrors
  # CsvImportRunner).
  def start(automatic: false)
    validate!
    BackupRepository.clear_error!
    RunnerLog.record_started!(:backup, automatic:)
    self.class.spawn_preparing_thread!(self)
  end

  def unavailable_reason
    key = unavailable_reason_key
    key && reason(key)
  end

  def unavailable_reason_key
    # CSV import is checked first to match `validate!` priority — otherwise a
    # transient env hiccup (e.g. token reload mid-import) would show a stale
    # config error in the UI while the actual block is the running import.
    return :csv_import_in_progress if CsvImportRunner.in_progress?
    return :env_missing if env.nil?
    return :config_missing unless ::File.exist?(Configuration.path)
    return :influx_token_missing if env['INFLUX_ADMIN_TOKEN'].blank?
    return :destination_unconfigured if BackupRepository.host_directory.blank?

    database_unavailable_reason_key
  end

  def database_unavailable_reason_key
    return :postgres_not_running unless postgres_container_name
    return :influxdb_not_running unless influxdb_container_name
    return :influxdb_staging_not_mounted unless influxdb_staging_mounted?

    nil
  end

  def databases_configured?
    services = Compose.load.services
    services.exists?(POSTGRES_SERVICE) && services.exists?(INFLUXDB_SERVICE)
  end

  private

  # Body of the preparing thread: the slow pull + the container launch the
  # click no longer waits for. Failures here are surfaced exactly the way
  # the backup.sh sidecar surfaces its own — an error file in the runtime
  # dir that detect_completion! turns into a red completion card — so the
  # user gets the message on the progress page instead of a button spinner.
  def run_preparing!
    pull_image_if_needed!
    preflight_destination!
    run_container!
    BackupRepository.mark_pending!(backup_filename)
    BackupRepository::S3::Uploader.start_async(backup_filename) if BackupRepository.s3?
    self.class.invalidate_in_progress_cache!
  rescue StandardError => e
    logger.warn("backup preparing failed: #{e.class}: #{e.message}")
    capture_preparing_failure!(e)
  end

  # Mirror backup.sh's failure contract from the Ruby side: write the message
  # into /runtime/error.txt and drop a pending marker so detect_completion!
  # fires even if no /backups poll observed the (possibly very short)
  # preparing window, then refresh the cache for the next poll.
  def capture_preparing_failure!(error)
    BackupRepository.write_error_file!(error.message.presence || "#{error.class}: (no message)")
    BackupRepository.mark_pending!(backup_filename)
    self.class.invalidate_in_progress_cache!
  end

  def reason(key)
    I18n.t("backups.runner.unavailable_reasons.#{key}")
  end

  def validate!
    raise Error, error(:already_in_progress) if self.class.preparing? || self.class.running?
    raise Error, error(:restore_in_progress) if RestoreRunner.running?
    raise Error, error(:csv_import_in_progress) if CsvImportRunner.in_progress?

    reason = unavailable_reason
    raise Error, reason if reason
  end

  # External-only: probe the destination once via a short-lived sidecar
  # *before* spawning the long-running backup container. Catches the
  # common operational failures (NAS offline, USB unplugged, mount turned
  # read-only, root_squash permission-denied) up-front, so the user sees
  # a precise red banner on click instead of waiting for a generic
  # "process stopped" half a minute later. Skipped for local (no remote
  # to probe) and S3 (covered by the SDK during the upload phase).
  def preflight_destination!
    return unless BackupRepository.destination == 'external'

    result = Backups::ConnectionTest.new.call(
      check: 'external_path',
      values: { 'external_path' => BackupRepository.host_directory },
    )
    return if result.ok

    raise Error, error(:destination_unreachable, reason: I18n.t("configurations.connection_test.#{result.reason}"))
  end

  def docker_run_command
    [
      'docker', 'run', '--rm', '-d',
      '--name', CONTAINER_NAME,
      '-v', '/var/run/docker.sock:/var/run/docker.sock',
      # `--mount type=bind` (not `-v`) for the destination on purpose:
      # if the host source is missing (NAS offline, USB unplugged,
      # path renamed) `-v` would silently create an empty directory and
      # the backup would land in a phantom dir on the docker host, lost
      # the moment the real mount returns. `--mount` fails the container
      # start instead — the controller surfaces that as a clean error.
      '--mount', "type=bind,source=#{BackupRepository.host_directory},target=/output",
      '-v', "#{self.class.host_runtime_directory}:#{RUNTIME_MOUNT}",
      '-v', "#{self.class.host_influx_staging_directory}:#{INFLUX_STAGING_MOUNT}",
      '-v', "#{host_config_path}:/config.yaml:ro",
      '--entrypoint', 'sh',
      IMAGE,
      '-c', self.class.script, '_',
      influx_admin_token, backup_filename, backup_date,
      postgres_container_name, influxdb_container_name
    ]
  end

  def host_config_path
    ::File.join(Orchestration::Runner.host_data_path, 'helios', 'config.yaml')
  end

  def postgres_container_name
    @postgres_container_name ||= Orchestration::Container.find(POSTGRES_SERVICE)&.name
  end

  def influxdb_container_name
    influxdb_container&.name
  end

  def influxdb_container
    @influxdb_container ||= Orchestration::Container.find(INFLUXDB_SERVICE)
  end

  # The sidecar and the InfluxDB container exchange the dump through the
  # shared INFLUX_STAGING_MOUNT bind mount. A container created before that
  # mount existed in compose.yaml — typically adopted from a pre-HELIOS
  # installation and never recreated (issue #291) — writes the backup into
  # its own overlay filesystem instead: `influx backup` succeeds, but the
  # staging dir stays empty and the run dies with the cryptic "InfluxDB
  # backup produced no output". Catch it up-front with a precise reason.
  def influxdb_staging_mounted?
    influxdb_container&.mount_source(INFLUX_STAGING_MOUNT).present?
  end

  def env
    return @env if defined?(@env)

    @env = Env.load
  end

  def influx_admin_token
    @influx_admin_token ||= env&.[]('INFLUX_ADMIN_TOKEN')
  end

  def backup_filename
    @backup_filename ||= "solectrus-backup-#{timestamp.strftime('%Y%m%d-%H%M%S')}.tar"
  end

  def backup_date
    @backup_date ||= timestamp.strftime('%Y-%m-%d')
  end

  # The filename/date encode wall-clock time in the app timezone
  # (config.time_zone, derived from the TZ env var). Web requests and the
  # scheduler thread share that zone, so Time.current is correct in either —
  # and BackupRepository.created_at_from parses it back with the same Time.zone.
  def timestamp
    @timestamp ||= Time.current
  end
end
