require 'open3'

# Runs the backup as a separate, detached `docker:cli` container.
# Independence from the HELIOS Rails process is the whole point: the
# backup keeps running when the user closes the browser and even when
# HELIOS itself is restarted (e.g. during a Watchtower self-update).
#
# Mutual exclusion is enforced by the fixed container name —
# `docker run --name helios-backup-runner` fails if the name is taken,
# so a second concurrent backup cannot start.
#
# Status is read directly from Docker (`docker inspect`); no marker
# files in the data directory are needed for "in progress".
class BackupRunner
  class Error < StandardError; end

  CONTAINER_NAME = 'helios-backup-runner'.freeze
  IMAGE = 'docker:cli'.freeze
  POSTGRES_SERVICE = 'postgresql'.freeze
  INFLUXDB_SERVICE = 'influxdb'.freeze
  IN_PROGRESS_CACHE_KEY = 'helios_backup_runner_in_progress'.freeze
  IN_PROGRESS_CACHE_TTL = 3.seconds

  SCRIPT = ::File.read(::File.join(__dir__, 'backup_runner', 'backup.sh')).freeze

  class << self
    delegate :start, to: :new

    # Reason why a fresh backup cannot be started right now, or nil if it can.
    # In-progress states are excluded — the UI surfaces those separately.
    delegate :unavailable_reason, to: :new

    # Whether both database services exist in compose.yaml. When they don't,
    # the Backup tab shows an empty state; when they merely aren't running,
    # the create form stays visible with a disabled button.
    delegate :databases_configured?, to: :new

    def in_progress
      Current.instance.fetch(:backup_runner_in_progress) do
        Rails
          .cache
          .fetch(IN_PROGRESS_CACHE_KEY, expires_in: IN_PROGRESS_CACHE_TTL) do
            container =
              Orchestration::DockerCli.running_container(CONTAINER_NAME)
            next nil unless container

            BackupRepository::InProgress.new(
              started_at: container.started_at,
              filename: container.args[4],
            )
          end
      end
    end

    def invalidate_in_progress_cache!
      Rails.cache.delete(IN_PROGRESS_CACHE_KEY)
    end
  end

  def start
    validate!
    pull_image_if_needed!
    BackupRepository.prune!
    BackupRepository.clear_error!
    run_container!
    BackupRepository.mark_pending!
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
    raise Error, I18n.t('backups.runner.errors.restore_in_progress') if RestoreRunner.in_progress

    reason = unavailable_reason
    raise Error, reason if reason
  end

  def pull_image_if_needed!
    return if Orchestration::DockerCli.image_present?(IMAGE)

    ok, output = Orchestration::DockerCli.pull_image(IMAGE)
    return if ok

    raise Error, I18n.t('backups.runner.errors.image_pull_failed', output: output.strip)
  end

  def run_container!
    FileUtils.mkdir_p(BackupRepository.directory) if BackupRepository.directory

    output, status = Open3.capture2e(*docker_run_command)
    return if status.success?

    raise Error, I18n.t('backups.runner.errors.already_in_progress') if output.include?('is already in use')

    raise Error, I18n.t('backups.runner.errors.start_failed', output: output.strip)
  end

  def docker_run_command
    [
      'docker', 'run', '--rm', '-d',
      '--name', CONTAINER_NAME,
      '-v', '/var/run/docker.sock:/var/run/docker.sock',
      '-v', "#{BackupRepository.host_directory}:/output",
      '-v', "#{host_config_path}:/config.yaml:ro",
      *aws_env_args,
      '--entrypoint', 'sh',
      IMAGE,
      '-c', SCRIPT, '_',
      influx_admin_token, backup_filename, backup_date,
      postgres_container_name, influxdb_container_name,
      BackupRepository.destination, BackupRepository.host_directory.to_s,
      BackupRepository::S3::IMAGE, s3_dir_uri
    ]
  end

  # AWS credentials and optional endpoint are forwarded to the outer
  # docker:cli container so backup.sh can re-export them to the nested
  # aws-cli sidecar that performs the actual upload. Only set when the
  # active destination is S3 — keeps the env clean for the local case
  # and avoids leaking credentials into unrelated runs.
  def aws_env_args
    return [] unless BackupRepository.s3?

    backup = Configuration.current.backup
    args = [
      '-e', "AWS_ACCESS_KEY_ID=#{backup.aws_access_key_id}",
      '-e', "AWS_SECRET_ACCESS_KEY=#{backup.aws_secret_access_key}",
      '-e', "AWS_DEFAULT_REGION=#{backup.aws_region}"
    ]
    endpoint = backup.s3_endpoint_url.to_s.strip
    args.push('-e', "AWS_ENDPOINT_URL=#{endpoint}") if endpoint.present?
    args
  end

  def s3_dir_uri
    BackupRepository.s3? ? BackupRepository::S3.s3_dir_uri : ''
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
