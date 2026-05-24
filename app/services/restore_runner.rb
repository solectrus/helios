# Restores a stored HELIOS backup in a detached `docker:cli` container (see
# DetachedRunner for the shared launch / in-progress machinery). It clears
# the database directories, starts empty database services from the
# restored configuration and imports PostgreSQL plus InfluxDB.
class RestoreRunner < DetachedRunner
  CONTAINER_NAME = 'helios-restore-runner'.freeze
  IMAGE = BackupRunner::IMAGE
  POSTGRES_SERVICE = BackupRunner::POSTGRES_SERVICE
  INFLUXDB_SERVICE = BackupRunner::INFLUXDB_SERVICE
  ERROR_FILENAME = 'restore-error.txt'.freeze
  I18N_SCOPE = 'backups.restorer'.freeze

  SCRIPT = ::File.read(::File.join(__dir__, 'restore_runner', 'restore.sh')).freeze

  class << self
    def clear_error!
      BackupRepository.clear_error!(ERROR_FILENAME)
    end

    # Extends the inherited in_progress with an S3 download phase: for
    # S3-sourced restores HELIOS fetches the tar before the detached
    # container runs, and the Downloader surfaces the running thread so
    # the UI keeps showing "in progress" during that fetch.
    def in_progress
      super || s3_download_in_progress
    end

    def s3_download_in_progress
      return nil unless BackupRepository.s3?

      BackupRepository::S3::Downloader.current
    end
  end

  def start(filename) # rubocop:disable Metrics/MethodLength
    @backup = BackupRepository.find!(filename)
    validate!
    pull_image_if_needed!
    clear_errors!
    BackupRepository.mark_pending!

    if BackupRepository.s3?
      # The restored config will overwrite the current (S3) credentials,
      # so the download has to happen FIRST — and inside the thread, so
      # we run the config switch and container start only after the tar
      # is in staging. The request returns immediately; failures show up
      # via restore-error.txt in detect_completion!.
      BackupRepository::S3::Downloader.start_async(backup.filename) do
        prepare_restored_stack!
        run_container!
      end
    else
      prepare_restored_stack!
      run_container!
    end

    self.class.invalidate_in_progress_cache!
  rescue BackupRepository::NotFound
    raise Error, error(:backup_not_found)
  end

  private

  attr_reader :backup

  def validate!
    validate_archive!
    raise Error, error(:backup_in_progress) if BackupRunner.running?
    raise Error, error(:already_in_progress) if self.class.in_progress
  end

  def validate_archive!
    raise Error, error(:missing_config) if restored_configuration_data.blank?
    raise Error, error(:missing_postgres) unless postgresql_entry?
    raise Error, error(:missing_influx) unless influxdb_entry?
  end

  def prepare_restored_stack!
    write_restored_configuration!(restored_configuration_data.deep_dup)
    Export::Builder.new(Configuration.current).write!
    raise Error, error(:missing_token) if influx_admin_token.blank?
  end

  def write_restored_configuration!(data)
    tmp_path = "#{Configuration.path}.tmp"
    ::File.write(tmp_path, Configuration.dump(data))
    ::File.rename(tmp_path, Configuration.path)
    Current.configuration = nil
  end

  def clear_errors!
    BackupRepository.clear_error!
    self.class.clear_error!
  end

  def docker_run_command
    [
      'docker', 'run', '--rm', '-d',
      '--name', CONTAINER_NAME,
      '-v', '/var/run/docker.sock:/var/run/docker.sock',
      '-v', "#{BackupRepository.host_directory}:/output",
      *data_mount_args,
      '--entrypoint', 'sh', IMAGE, '-c', SCRIPT, '_',
      *positional_args
    ]
  end

  def positional_args
    [
      influx_admin_token, backup.filename, host_data_path,
      postgresql_data_path, influxdb_data_path, redis_data_path,
      restart_after_flag, services_except_self.join(' '),
      ::Compose.filename
    ]
  end

  def data_mount_args
    args = ['-v', "#{host_data_path}:/data"]
    args.push('-v', "#{host_data_path}:#{host_data_path}") unless host_data_path == '/data'
    data_paths.each do |path|
      args.push('-v', "#{path}:#{path}") if mount_data_path?(path)
    end
    args
  end

  def mount_data_path?(path)
    Pathname.new(path).absolute? && !path.start_with?("#{host_data_path}/")
  end

  def host_data_path
    @host_data_path ||= Orchestration::Runner.host_data_path
  end

  # "1" iff every configured service (minus HELIOS itself) is currently
  # running. The restore script restarts the stack only in that case;
  # otherwise it leaves manually-stopped services alone after the restore.
  def restart_after_flag
    running = Orchestration::Container.all.select(&:running?).filter_map(&:service_name)
    (services_except_self - running).empty? ? '1' : '0'
  end

  # The HELIOS service must never appear in compose down/up calls issued by
  # the restore script — stopping our own container would kill the user's
  # UI mid-restore. Mirrors `Orchestration::Runner.services_except_self`.
  def services_except_self
    @services_except_self ||= ::Compose.load.services.names - [Orchestration::Runner::SELF_SERVICE]
  end

  def influx_admin_token
    @influx_admin_token ||= Env.load&.[]('INFLUX_ADMIN_TOKEN')
  end

  def data_paths
    @data_paths ||= [postgresql_data_path, influxdb_data_path, redis_data_path].uniq
  end

  def restored_configuration_data
    archive_contents.config
  end

  def postgresql_entry?
    archive_contents.entries.any? { |entry| entry.name.match?(BackupRepository::POSTGRESQL_ENTRY_PATTERN) }
  end

  def influxdb_entry?
    archive_contents.entries.any? { |entry| entry.name.match?(BackupRepository::INFLUXDB_ENTRY_PATTERN) }
  end

  def archive_contents
    @archive_contents ||= BackupRepository.read_archive_for(backup.filename)
  end

  def postgresql_data_path
    storage_path_for('postgresql', POSTGRES_SERVICE)
  end

  def influxdb_data_path
    storage_path_for('influxdb', INFLUXDB_SERVICE)
  end

  def redis_data_path
    storage_path_for('redis', 'redis')
  end

  def storage_path_for(section, default_dir)
    configured = Configuration.current.public_send(section).volume_path.presence
    path = configured || ::File.join(host_data_path, default_dir)
    return path if Pathname.new(path).absolute?

    ::File.expand_path(path, host_data_path)
  end
end
