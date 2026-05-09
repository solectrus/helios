require 'open3'

# Restores a stored HELIOS backup in a detached `docker:cli` container.
# The runner keeps working even if the browser is closed. It clears the
# database directories, starts empty database services from the restored
# configuration and imports PostgreSQL plus InfluxDB from the archive.
class RestoreRunner
  class Error < StandardError; end

  CONTAINER_NAME = 'helios-restore-runner'.freeze
  IMAGE = BackupRunner::IMAGE
  POSTGRES_SERVICE = BackupRunner::POSTGRES_SERVICE
  INFLUXDB_SERVICE = BackupRunner::INFLUXDB_SERVICE
  ERROR_FILENAME = 'restore-error.txt'.freeze

  SCRIPT = ::File.read(::File.join(__dir__, 'restore_runner', 'restore.sh')).freeze

  class << self
    delegate :start, to: :new

    def in_progress
      Current.instance.fetch(:restore_runner_in_progress) do
        container = Orchestration::DockerCli.running_container(CONTAINER_NAME)
        next nil unless container

        BackupRepository::InProgress.new(
          started_at: container.started_at,
          filename: container.args[4],
        )
      end
    end

    def error_message
      BackupRepository.error_message(ERROR_FILENAME)
    end

    def clear_error!
      BackupRepository.clear_error!(ERROR_FILENAME)
    end
  end

  def start(filename)
    @backup = BackupRepository.find!(filename)
    validate!
    pull_image_if_needed!
    prepare_restored_stack!
    clear_errors!
    run_container!
  rescue BackupRepository::NotFound
    raise Error, error(:backup_not_found)
  end

  private

  attr_reader :backup

  def error(key, **)
    I18n.t("backups.restorer.errors.#{key}", **)
  end

  def validate!
    validate_archive!
    raise Error, error(:backup_in_progress) if BackupRunner.in_progress
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

  def pull_image_if_needed!
    return if Orchestration::DockerCli.image_present?(IMAGE)

    ok, output = Orchestration::DockerCli.pull_image(IMAGE)
    return if ok

    raise Error, error(:image_pull_failed, output: output.strip)
  end

  def clear_errors!
    BackupRepository.clear_error!
    self.class.clear_error!
  end

  def run_container!
    FileUtils.mkdir_p(BackupRepository.directory)

    output, status = Open3.capture2e(*docker_run_command)
    return if status.success?

    raise Error, error(:already_in_progress) if output.include?('is already in use')

    raise Error, error(:start_failed, output: output.strip)
  end

  def docker_run_command
    [
      'docker', 'run', '--rm', '-d',
      '--name', CONTAINER_NAME,
      '-v', '/var/run/docker.sock:/var/run/docker.sock',
      '-v', "#{BackupRepository.host_directory}:/output",
      *data_mount_args,
      '--entrypoint', 'sh',
      IMAGE, '-c', SCRIPT, '_',
      influx_admin_token, backup.filename, host_data_path,
      postgresql_data_path, influxdb_data_path, redis_data_path,
      restart_after_flag, services_except_self.join(' ')
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
    @archive_contents ||= BackupRepository.read_archive(backup.path)
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
