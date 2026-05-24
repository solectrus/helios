# Runs the backup as a detached `docker:cli` container (see DetachedRunner
# for the shared launch / in-progress machinery).
class BackupRunner < DetachedRunner
  CONTAINER_NAME = 'helios-backup-runner'.freeze
  IMAGE = 'docker:29-cli'.freeze
  POSTGRES_SERVICE = 'postgresql'.freeze
  INFLUXDB_SERVICE = 'influxdb'.freeze
  I18N_SCOPE = 'backups.runner'.freeze

  SCRIPT = ::File.read(::File.join(__dir__, 'backup_runner', 'backup.sh')).freeze

  class << self
    # Reason why a fresh backup cannot be started right now, or nil if it can.
    # In-progress states are excluded — the UI surfaces those separately.
    delegate :unavailable_reason, to: :new

    # Whether both database services exist in compose.yaml. When they don't,
    # the Backup tab shows an empty state; when they merely aren't running,
    # the create form stays visible with a disabled button.
    delegate :databases_configured?, to: :new

    # Extends the inherited in_progress with the S3 upload phase, and
    # re-spawns the uploader if a HELIOS restart killed the thread while
    # the staged tar is still on disk.
    def in_progress
      super || s3_upload_in_progress_or_resume
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
  end

  def start
    validate!
    pull_image_if_needed!
    BackupRepository.prune!
    BackupRepository.clear_error!
    run_container!
    BackupRepository.mark_pending!(backup_filename)
    BackupRepository::S3::Uploader.start_async(backup_filename) if BackupRepository.s3?
    self.class.invalidate_in_progress_cache!
  end

  def unavailable_reason
    return reason(:env_missing) if env.nil?
    return reason(:config_missing) unless ::File.exist?(Configuration.path)
    return reason(:influx_token_missing) if env['INFLUX_ADMIN_TOKEN'].blank?
    return reason(:destination_unconfigured) if BackupRepository.host_directory.blank?
    return reason(:postgres_not_running) unless postgres_container_name
    return reason(:influxdb_not_running) unless influxdb_container_name

    nil
  end

  def databases_configured?
    services = Compose.load.services
    services.exists?(POSTGRES_SERVICE) && services.exists?(INFLUXDB_SERVICE)
  end

  private

  def reason(key)
    I18n.t("backups.runner.unavailable_reasons.#{key}")
  end

  def validate!
    raise Error, error(:restore_in_progress) if RestoreRunner.running?

    reason = unavailable_reason
    raise Error, reason if reason
  end

  def docker_run_command
    [
      'docker', 'run', '--rm', '-d',
      '--name', CONTAINER_NAME,
      '-v', '/var/run/docker.sock:/var/run/docker.sock',
      '-v', "#{BackupRepository.host_directory}:/output",
      '-v', "#{host_config_path}:/config.yaml:ro",
      '--entrypoint', 'sh',
      IMAGE,
      '-c', SCRIPT, '_',
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
    @influxdb_container_name ||= Orchestration::Container.find(INFLUXDB_SERVICE)&.name
  end

  def env
    return @env if defined?(@env)

    @env = Env.load
  end

  def influx_admin_token
    @influx_admin_token ||= env&.[]('INFLUX_ADMIN_TOKEN')
  end

  def backup_filename
    @backup_filename ||= "solectrus-backup-#{Time.current.strftime('%Y%m%d-%H%M%S')}.tar"
  end

  def backup_date
    @backup_date ||= Time.current.strftime('%Y-%m-%d')
  end
end
