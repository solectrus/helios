require 'open3'

# Base for the detached backup and restore runners. Each runs its work in a
# separate, detached `docker:cli` container — independence from the HELIOS
# Rails process is the whole point: the run survives the browser closing
# and even a HELIOS restart (e.g. a Watchtower self-update).
#
# Mutual exclusion is enforced by the fixed container name —
# `docker run --name <CONTAINER_NAME>` fails if the name is taken, so a
# second run of the same kind cannot start. Status is read straight from
# Docker (`docker inspect`); no marker files are needed for "in progress".
#
# Subclasses must define the constants CONTAINER_NAME, IMAGE and I18N_SCOPE
# and the instance method `docker_run_command`.
class DetachedRunner
  class Error < StandardError; end

  # Docker-inspect is comparatively expensive, so the "is a run live?"
  # answer is cached briefly — long enough to spare every /backups render
  # its own probe, short enough to still feel live.
  IN_PROGRESS_CACHE_TTL = 3.seconds

  # Local sidecar directory bind-mounted into every runner as `/runtime`.
  # Phase markers (and any other short-lived control files HELIOS reads
  # while a run is live) belong here, not in the backup destination —
  # an external (NAS, SMB) or S3 staging mount must not be touched on
  # every /backups poll just to read a couple of bytes.
  RUNTIME_DIRNAME = 'runners'.freeze
  RUNTIME_MOUNT = '/runtime'.freeze

  class << self
    delegate :start, to: :new

    # The live run as a BackupRepository::InProgress struct, or nil. The
    # container-detection half is cached (per request + IN_PROGRESS_CACHE_TTL)
    # because it is read on every /backups render; the phase marker is read
    # fresh on every call — it flips every few seconds and the auto-reload
    # UI polls /backups every 3 s, so caching it would just add a lag
    # without saving meaningful IO.
    def in_progress
      base = container_in_progress
      return nil unless base

      phase = current_phase
      return base unless phase

      BackupRepository::InProgress.new(
        started_at: base.started_at, filename: base.filename, phase: phase,
      )
    end

    # Uncached "is this runner's container live right now?". The cross-runner
    # exclusion check in `validate!` must not read the IN_PROGRESS_CACHE_TTL
    # cache: a backup and a restore starting within the same window could
    # both observe a stale nil and both launch — and a restore wipes the
    # database directories a concurrent backup is still reading.
    def running?
      Orchestration::DockerCli.running_container(self::CONTAINER_NAME).present?
    end

    def invalidate_in_progress_cache!
      Rails.cache.delete(in_progress_cache_key)
    end

    # Current script phase, read fresh from PHASE_FILENAME in the local
    # runtime directory. Returns nil if the subclass declares no marker
    # file, the file is absent (window before the first set_phase write
    # or after a successful cleanup), or its content is not in the
    # allowlist.
    def current_phase
      filename = phase_filename
      return nil unless filename

      raw = ::File.read(::File.join(runtime_directory, filename)).strip
      phase = raw.to_sym
      self::KNOWN_PHASES.include?(phase) ? phase : nil
    rescue Errno::ENOENT
      nil
    end

    # HELIOS-side path of the runtime directory — read directly by
    # `current_phase` on every /backups poll.
    def runtime_directory
      ::File.join(Rails.configuration.data_path, 'helios', RUNTIME_DIRNAME)
    end

    # Host-side equivalent — the bind-mount source passed to `docker run`.
    def host_runtime_directory
      ::File.join(Orchestration::Runner.host_data_path, 'helios', RUNTIME_DIRNAME)
    end

    private

    def container_in_progress
      Current.instance.fetch(:"#{name.underscore}_in_progress") do
        Rails.cache.fetch(in_progress_cache_key, expires_in: IN_PROGRESS_CACHE_TTL) do
          container = Orchestration::DockerCli.running_container(self::CONTAINER_NAME)
          next nil unless container

          BackupRepository::InProgress.new(started_at: container.started_at, filename: container.args[4])
        end
      end
    end

    def phase_filename
      return nil unless const_defined?(:PHASE_FILENAME)

      self::PHASE_FILENAME
    end

    def in_progress_cache_key
      "helios_#{name.underscore}_in_progress"
    end
  end

  private

  def pull_image_if_needed!
    image = self.class::IMAGE
    return if Orchestration::DockerCli.image_present?(image)

    ok, output = Orchestration::DockerCli.pull_image(image)
    return if ok

    raise Error, error(:image_pull_failed, output: output.strip)
  end

  def run_container!
    FileUtils.mkdir_p(BackupRepository.directory) if BackupRepository.directory
    FileUtils.mkdir_p(self.class.runtime_directory)

    output, status = Open3.capture2e(*docker_run_command)
    return if status.success?

    raise Error, error(:already_in_progress) if output.include?('is already in use')

    raise Error, error(:start_failed, output: output.strip)
  end

  # Localized error string from the subclass's i18n namespace
  # (backups.runner.errors.* or backups.restorer.errors.*).
  def error(key, **)
    I18n.t("#{self.class::I18N_SCOPE}.errors.#{key}", **)
  end
end
