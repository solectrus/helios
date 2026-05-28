require 'open3'
require 'timeout'

# Runs solectrus/csv-importer as a detached container against the local
# SOLECTRUS stack. Reads the extracted CSV tree from CsvImportUploader,
# bind-mounts it as /data, and passes through InfluxDB credentials,
# sensor mappings and SENEC_IGNORE from the live `.env` so imported
# points land on the same measurement+field pairs the dashboard reads.
#
# `--rm` is intentionally NOT used: the exit code (and last log lines)
# must remain inspectable across the gap between container exit and the
# next /show poll. `process_completion!` removes the container after
# reading its result.
#
# Lifecycle has four phases the user sees as equal steps:
#   1. preparing  — image pull + `docker run`
#   2. importing  — csv-importer container writes points to InfluxDB
#   3. flushing   — Redis cache flush so the dashboard rebuilds aggregates
#   4. truncating — reset summaries so daily aggregates refill from raw.
#                   When CoveredDates can infer the imported days from
#                   filenames we DELETE only those rows; otherwise we
#                   TRUNCATE the whole table.
#
# Phases 3 and 4 run inside a completion thread (so the /show poll request
# does not block on them) and their results are part of the user-visible
# outcome: the success file is only written if both succeed.
class CsvImportRunner < DetachedRunner # rubocop:disable Metrics/ClassLength
  CONTAINER_NAME = 'helios-csv-import-runner'.freeze
  IMAGE = 'ghcr.io/solectrus/csv-importer:develop'.freeze
  INFLUXDB_SERVICE = 'influxdb'.freeze
  REDIS_SERVICE = 'redis'.freeze
  IMPORT_MOUNT = '/data'.freeze
  I18N_SCOPE = 'csv_imports.runner'.freeze

  # Always required for the importer to write into InfluxDB.
  REQUIRED_INFLUX_KEYS = %w[INFLUX_TOKEN_WRITE INFLUX_ORG INFLUX_BUCKET].freeze
  # In collectors_only mode the InfluxDB host is external and must also be
  # set explicitly; otherwise the importer connects to the compose service
  # name and the host is synthesized.
  EXTRA_COLLECTORS_ONLY_INFLUX_KEYS = %w[INFLUX_HOST].freeze

  # Passed through so historical points land on the same measurement+field
  # pairs the dashboard already reads.
  SENSOR_MAPPING_KEYS = %w[
    INFLUX_SENSOR_INVERTER_POWER
    INFLUX_SENSOR_HOUSE_POWER
    INFLUX_SENSOR_GRID_IMPORT_POWER
    INFLUX_SENSOR_GRID_EXPORT_POWER
    INFLUX_SENSOR_BATTERY_CHARGE_POWER
    INFLUX_SENSOR_BATTERY_DISCHARGE_POWER
  ].freeze

  class << self
    delegate :unavailable_reason, :precheck!, to: :new
    delegate :error_message, :success_message, :clear_error!, :clear_success!, to: 'CsvImportRunner::State'

    # True while preparing thread is alive, the container is up, OR the
    # completion thread (flushing + truncating phases) is still running.
    # Keeps the user on the progress page across all phases.
    def in_progress? = preparing? || running? || completing?

    # True while the background thread is pulling the image + launching the
    # container. Process-local; killed by a HELIOS restart — the user then
    # simply re-uploads.
    def preparing?
      mutex.synchronize { @preparing_thread&.alive? || false }
    end

    # True while the completion thread (post-exit phases 3+4) is still
    # running. Same lifecycle as preparing — survives only within a
    # single HELIOS process.
    def completing?
      mutex.synchronize { @completion_thread&.alive? || false }
    end

    # Hands the slow pull + launch work off to a thread so the controller
    # can redirect to the progress page immediately. Mirrors
    # BackupRepository::S3::AsyncWorker (single-flight, Rails-executor
    # wrapped, errors captured into the state file).
    def spawn_preparing_thread!(instance)
      mutex.synchronize do
        return if @preparing_thread&.alive?

        zone = Time.zone
        @preparing_thread = Thread.new do # rubocop:disable ThreadSafety/NewThread
          Time.zone = zone if zone
          Rails.application.executor.wrap { instance.send(:run_preparing!) }
        end
      end
    end

    # Spawns the post-exit completion thread (reads container outcome,
    # runs flushing + truncating phases). Single-flight: a second call
    # while the first thread is alive is a no-op, so two parallel /show
    # polls reaching detect_completion! at the same time don't both run
    # TRUNCATE summaries + Redis FLUSHALL.
    def spawn_completion_thread!(raw)
      mutex.synchronize do
        return if @completion_thread&.alive?

        @completion_phase = nil
        zone = Time.zone
        @completion_thread = Thread.new do # rubocop:disable ThreadSafety/NewThread
          Time.zone = zone if zone
          Rails.application.executor.wrap { new.process_completion!(raw) }
        end
      end
    end

    # Active phase of the completion thread (:flushing or :truncating).
    # Read by `progress` so the UI can highlight the correct step.
    def completion_phase
      mutex.synchronize { @completion_phase }
    end

    def completion_phase=(phase)
      mutex.synchronize { @completion_phase = phase }
    end

    # Read on every /show poll; a hung docker daemon must not pile up Puma
    # workers blocked on docker-logs. The timeout is generous because docker
    # logs is normally a sub-second tail read.
    LOG_TAIL_TIMEOUT = 5
    private_constant :LOG_TAIL_TIMEOUT

    def log_tail(lines = 50)
      Timeout.timeout(LOG_TAIL_TIMEOUT) do
        output, = Open3.capture2e('docker', 'logs', '--tail', lines.to_s, CONTAINER_NAME)
        output
      end
    rescue StandardError
      ''
    end

    # Live progress for the UI. Phase follows the active thread:
    # :preparing while the prep thread is alive, :importing while the
    # container is up, then :flushing / :truncating while the completion
    # thread runs phases 3 and 4. During completion the phase is only set
    # by `run_phase!` (success path); on the failure path it stays nil so
    # the UI doesn't pretend flushing/truncating ran — the component falls
    # back to :importing for nil, which matches what just happened.
    def progress
      return { phase: :preparing, done: 0, total: 0 } if preparing?
      return { phase: completion_phase, done: 0, total: 0 } if completing?

      done = LogParser.progress(log_tail(1000))[:done]
      total = Dir.glob(
        "#{CsvImportUploader.extract_directory}/**/*.csv", File::FNM_CASEFOLD
      ).size
      { phase: :importing, done: done, total: total }
    end

    # If the container has exited, hand off to the completion thread.
    # spawn_completion_thread!'s mutex + alive? check is the single-flight
    # gate — two parallel /show polls (or the before_action firing on
    # overlapping requests) cannot both spawn a completion thread.
    def detect_completion!
      raw = Orchestration::DockerCli.inspect_container(CONTAINER_NAME)
      return if raw.nil?
      return if raw.dig('State', 'Running')

      spawn_completion_thread!(raw)
    end

    private

    def mutex
      @mutex ||= Mutex.new # rubocop:disable ThreadSafety/ClassInstanceVariable
    end
  end

  def start
    validate!
    State.clear_all!
    self.class.spawn_preparing_thread!(self)
  end

  # Cheap pre-flight the controller runs BEFORE accepting an upload so the
  # uploader's destructive cleanup (`rm_rf extract_directory`, which is the
  # bind-mount source for a possibly-running container) cannot fire while
  # an import is in flight or another runner holds the lock. Mirrors
  # `validate!` minus the extracted-CSV check, which can only run after the
  # uploader has finished extracting.
  def precheck!
    check_no_concurrent_runs!

    msg = unavailable_reason
    raise Error, msg if msg
  end

  # Preconditions for the import UI: things the user cannot fix by
  # re-uploading. The CSV-files check stays out — that's a runtime check
  # enforced in `check_ready_to_import!`.
  def unavailable_reason
    return reason(:env_missing) if env.nil?
    return reason(:postgresql_not_running) unless postgresql_running?
    return reason(:influxdb_not_running) unless influxdb_target_running?
    return reason(:influx_target_missing) if influx_credentials_missing?

    nil
  end

  # Body of the preparing thread; surfaces failures into the state file so
  # the UI can show them on the next poll.
  def run_preparing!
    pull_image_if_needed!
    run_container!
    self.class.invalidate_in_progress_cache!
  rescue StandardError => e
    Rails.logger.warn("[CsvImportRunner] preparing failed: #{e.class}: #{e.message}")
    State.write_error!(e.message.presence || "#{e.class}: (no message)")
    CsvImportUploader.cleanup!
  end

  # Body of the completion thread. Reads the just-exited container's
  # state, then — on a clean import — awaits the flushing and truncating
  # phases before writing the final success file so the user-visible
  # outcome reflects whether the dashboard caches were actually reset.
  def process_completion!(raw) # rubocop:disable Metrics/AbcSize
    Rails.logger.info('[CsvImportRunner] container finished, processing completion')
    state = raw['State'] || {}

    if successful_exit?(state)
      capture_outcome!(raw)
    else
      capture_failure!(raw)
    end
  rescue StandardError => e
    Rails.logger.warn("[CsvImportRunner] completion failed: #{e.class}: #{e.message}")
    State.write_error!(e.message.presence || "#{e.class}: (no message)")
  ensure
    self.class.completion_phase = nil
    # Each ensure step is wrapped: an exception raised from the ensure block
    # would bypass the `rescue StandardError` above (Ruby semantics), leaving
    # the in_progress cache stale and the UI stuck at "running" forever.
    safely(:remove_container) { remove_container! }
    safely(:cleanup) { CsvImportUploader.cleanup! }
    self.class.invalidate_in_progress_cache!
  end

  private

  def reason(key)
    I18n.t("#{self.class::I18N_SCOPE}.unavailable.#{key}")
  end

  def validate!
    precheck!
    check_ready_to_import!
  end

  # Cross-runner exclusion uses `.in_progress` (struct or nil) rather than
  # `.running?` so it also covers the S3 download window of an external
  # restore (no container yet) and the S3 upload tail of an external
  # backup (container already exited).
  def check_no_concurrent_runs!
    raise Error, error(:already_in_progress) if self.class.in_progress?
    raise Error, error(:exit_pending) if exited_container_pending?
    raise Error, error(:backup_in_progress) if BackupRunner.in_progress
    raise Error, error(:restore_in_progress) if RestoreRunner.in_progress
  end

  def check_ready_to_import!
    raise Error, reason(:no_csv_files) unless extracted_csvs?
  end

  # Defense-in-depth: a stopped container with our reserved name would
  # block `docker run --name`. The controller polls detect_completion!
  # before each form render, so this should rarely fire.
  def exited_container_pending?
    raw = Orchestration::DockerCli.inspect_container(CONTAINER_NAME)
    raw && !raw.dig('State', 'Running')
  end

  def extracted_csvs?
    extracted_csv_paths.any?
  end

  def env
    return @env if defined?(@env)

    @env = Env.load
  end

  def influx_credentials_missing?
    keys = REQUIRED_INFLUX_KEYS
    keys += EXTRA_COLLECTORS_ONLY_INFLUX_KEYS if Configuration.current.collectors_only?
    keys.any? { |key| env[key].blank? }
  end

  # In collectors_only mode InfluxDB lives outside our compose project, so
  # we cannot probe it directly; trust the credentials check and let the
  # importer surface a connection failure if the remote host is down.
  def influxdb_target_running?
    return true if Configuration.current.collectors_only?

    influxdb_container&.running? == true
  end

  # Required for the truncate summaries phase; skipped in collectors_only
  # mode (no local postgres there).
  def postgresql_running?
    return true if Configuration.current.collectors_only?

    Orchestration::Container.find(Orchestration::SummariesReset::SERVICE)&.running? == true
  end

  def influxdb_container
    @influxdb_container ||= Orchestration::Container.find(INFLUXDB_SERVICE)
  end

  def docker_run_command
    [
      'docker', 'run', '-d',
      '--name', CONTAINER_NAME,
      *network_args,
      '--mount', "type=bind,source=#{CsvImportUploader.host_extract_directory},target=#{IMPORT_MOUNT},readonly",
      *env_args,
      IMAGE
    ]
  end

  # Local stack: join the compose-network the InfluxDB container is on so
  # its service name resolves. collectors_only: external `INFLUX_HOST`,
  # the default bridge network is fine.
  def network_args
    return [] if Configuration.current.collectors_only?
    return [] unless influx_network_name

    ['--network', influx_network_name]
  end

  def influx_network_name
    return nil unless influxdb_container

    networks = influxdb_container.json&.dig('NetworkSettings', 'Networks')
    networks&.keys&.first
  end

  def env_args
    importer_env.flat_map { |key, value| ['-e', "#{key}=#{value}"] }
  end

  # ENV the importer respects. INFLUX_HOST is synthesized for the local
  # stack since we attach from outside compose and can't rely on its
  # service discovery.
  def importer_env
    influx_env
      .merge(sensor_mapping_env)
      .merge(senec_ignore_env)
      .compact
  end

  def influx_env
    {
      'INFLUX_ORG' => env['INFLUX_ORG'],
      'INFLUX_BUCKET' => env['INFLUX_BUCKET'],
      'INFLUX_TOKEN_WRITE' => env['INFLUX_TOKEN_WRITE'],
      'INFLUX_HOST' => influx_host,
      'INFLUX_PORT' => env['INFLUX_PORT'].presence || '8086',
      'INFLUX_SCHEMA' => influx_schema,
      'TZ' => env['TZ'].presence || 'Europe/Berlin',
    }
  end

  def influx_schema
    env['INFLUX_SCHEMA'].presence || (Configuration.current.collectors_only? ? 'https' : 'http')
  end

  def senec_ignore_env
    return {} if env['SENEC_IGNORE'].blank?

    { 'SENEC_IGNORE' => env['SENEC_IGNORE'] }
  end

  def influx_host
    if Configuration.current.collectors_only?
      env['INFLUX_HOST']
    else
      influxdb_container&.service_name || INFLUXDB_SERVICE
    end
  end

  def sensor_mapping_env
    SENSOR_MAPPING_KEYS.each_with_object({}) do |key, hash|
      value = env[key]
      hash[key] = value if value.present?
    end
  end

  # A container that exited cleanly: Docker reports it as `exited` (not
  # `created`/`dead`), exit code is 0, and it was not OOM-killed. Checking
  # ExitCode alone would let a `created` container (run -d succeeded, but
  # the OCI runtime never actually started the process) slip through as
  # "success" and trigger the flushing + truncating phases.
  def successful_exit?(state)
    state['Status'] == 'exited' &&
      state['ExitCode'].to_i.zero? &&
      !state['OOMKilled']
  end

  # On a clean container exit: count the imported files from the log; if
  # the count is missing or zero treat it as anomaly (capture_failure!).
  # Otherwise run the remaining phases SYNCHRONOUSLY in the completion
  # thread and only write the success file if BOTH succeed — a partial
  # failure leaves the dashboard cached and is surfaced to the user as
  # a failure rather than a silent warning in the log.
  def capture_outcome!(raw)
    count = LogParser.total_files(container_log_tail(500))
    return capture_failure!(raw) unless count.positive?

    failures = run_remaining_phases!
    if failures.empty?
      State.write_success!(count.to_s)
    else
      State.write_error!([error(:phases_failed_header), *failures].join("\n"))
    end
  end

  def run_remaining_phases!
    failures = []
    failures << error(:redis_flush_failed) unless run_phase!(:flushing) { flush_redis_cache! }
    failures << error(:summaries_reset_failed) unless run_phase!(:truncating) { reset_summaries! }
    failures
  end

  def run_phase!(phase)
    self.class.completion_phase = phase
    yield
  end

  # Dashboard caches series aggregates in Redis; without a flush, imported
  # historical periods stay invisible behind the cached empty results. A
  # missing/stopped redis container counts as success — nothing to flush.
  def flush_redis_cache!
    container = Orchestration::Container.find(REDIS_SERVICE)
    return true unless container&.running?

    Orchestration::RedisCacheFlush.call(container)
  rescue StandardError => e
    Rails.logger.warn("[CsvImportRunner] redis flush failed: #{e.class}: #{e.message}")
    false
  end

  # Daily summaries are an aggregated cache too — the dashboard would
  # otherwise stick with the pre-import aggregates for the imported range.
  # SOLECTRUS rebuilds the table from raw points on demand, so wiping is
  # the official reset path. We scope the reset to the days CoveredDates
  # extracts from filenames when possible; an unrecognized filename in
  # the upload flips us back to a full TRUNCATE. Skipped in
  # collectors_only mode (no local postgres there).
  def reset_summaries!
    return true if Configuration.current.collectors_only?

    # Defense against re-entry: if a previous process_completion! already
    # ran (extract dir was cleaned up in its ensure) but the container
    # removal failed, detect_completion! would re-process the same
    # container — without this check CoveredDates.scan would return nil
    # (empty dir) and SummariesReset(dates: nil) would TRUNCATE the entire
    # summaries table.
    return true if extracted_csv_paths.empty?

    dates = CoveredDates.scan(CsvImportUploader.extract_directory)
    Orchestration::SummariesReset.call(dates: dates)
  end

  def extracted_csv_paths
    Dir.glob("#{CsvImportUploader.extract_directory}/**/*.csv", File::FNM_CASEFOLD)
  end

  # `State.Error` is populated for OOM/image-pull failures; for the common
  # "importer raised, exited 1" case it is blank, so we fall back to the
  # last log lines so the user sees the actual backtrace, not just "exit 1".
  # The tail must be large enough to capture the exception line at the top
  # of a Ruby backtrace — a bundler/boot failure alone is ~20 `from` frames,
  # so anything smaller leaves the user with only the boilerplate footer.
  def capture_failure!(raw)
    state = raw['State'] || {}
    docker_err = state['Error'].to_s.strip
    tail = container_log_tail(500)
    msg =
      if docker_err.present? && tail.present?
        "#{docker_err}\n\n#{tail}"
      else
        docker_err.presence || tail.presence || error(:nonzero_exit, code: state['ExitCode'])
      end

    State.write_error!(msg)
  end

  def container_log_tail(lines)
    self.class.log_tail(lines).strip
  end

  def safely(label)
    yield
  rescue StandardError => e
    Rails.logger.warn("[CsvImportRunner] #{label} failed: #{e.class}: #{e.message}")
  end

  # A failed `docker rm` leaves the exited container in place — detect_completion!
  # would then trigger process_completion! again on the next /show poll, which
  # without the extracted_csv_paths guard in reset_summaries! would re-issue
  # destructive cache resets. Log loudly so the precondition stays visible.
  def remove_container!
    output, status = Open3.capture2e('docker', 'rm', '-f', CONTAINER_NAME)
    return if status.success?

    Rails.logger.warn(
      "[CsvImportRunner] docker rm failed (exit #{status.exitstatus}): #{output.strip}",
    )
  end

  # Override the inherited backup-flavoured mount-source prep: the csv
  # importer needs the runtime directory (for the error file) and an
  # extracted-CSV tree the uploader produces, but no backup destination
  # or influx staging mount.
  def ensure_bind_mount_sources!
    FileUtils.mkdir_p(self.class.runtime_directory)
    FileUtils.mkdir_p(CsvImportUploader.extract_directory)
  end
end
