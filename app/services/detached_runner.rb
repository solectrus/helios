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
# Subclasses must define the constants CONTAINER_NAME, IMAGE, I18N_SCOPE and
# UPDATE_PAUSE_REASON and the instance method `docker_run_command`.
class DetachedRunner
  include Loggable
  extend Loggable

  class Error < StandardError; end

  # Docker-inspect (an `Open3.capture2e('docker', 'inspect', ...)` subprocess)
  # is comparatively expensive, and /backups probes both the backup and the
  # restore container on every render — plus every 3 s while the auto-reload
  # poll runs during an operation. Liveness no longer rides on this TTL: the
  # Docker events listener invalidates the cache the moment the sidecar
  # starts or exits (HeliosOperationBroadcaster), and run_container!
  # invalidates on launch. The TTL is only a fallback for the window when no
  # events subscriber is connected, so it can be generous — a value equal to
  # the poll interval just guarantees a cold cache on most polls, spawning two
  # docker subprocesses per tick on slow hosts (e.g. Raspberry Pi).
  IN_PROGRESS_CACHE_TTL = 10.seconds

  # Local sidecar directory bind-mounted into every runner as `/runtime`.
  # Phase markers (and any other short-lived control files HELIOS reads
  # while a run is live) belong here, not in the backup destination —
  # an external (NAS, SMB) or S3 staging mount must not be touched on
  # every /backups poll just to read a couple of bytes.
  RUNTIME_DIRNAME = 'runners'.freeze
  RUNTIME_MOUNT = '/runtime'.freeze

  # Shared bind mount that lives on the InfluxDB container *and* the
  # backup/restore sidecar. `influx backup` writes its (already
  # gzipped) output directly into this directory, the sidecar tar-streams
  # it into the final archive in place, and `influx restore` reads it
  # back from here on a restore. The shared mount avoids a docker-exec
  # stdio pipe for multi-GB dumps and the wasted CPU of gzip-on-gzip.
  INFLUX_STAGING_DIRNAME = 'influx-backup-staging'.freeze
  INFLUX_STAGING_MOUNT = '/influx-backup-staging'.freeze

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

    # HELIOS-side path of the shared influx-staging directory.
    def influx_staging_directory
      ::File.join(Rails.configuration.data_path, INFLUX_STAGING_DIRNAME)
    end

    # Host-side equivalent — bind-mount source for the staging directory
    # that is shared between the InfluxDB service (see
    # Export::Services::Influxdb) and every backup/restore sidecar.
    def host_influx_staging_directory
      ::File.join(Orchestration::Runner.host_data_path, INFLUX_STAGING_DIRNAME)
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

  # Freezes automatic updates for the whole run, not just for the part that
  # happens inside the container: every runner does minutes of HELIOS-side
  # preparation first (pull an image, probe the destination, download from
  # S3, for a restore even rewrite compose.yaml), and an update landing in
  # that stretch breaks the run just as thoroughly — it recreates HELIOS
  # itself, and the preparation dies with it. Called at the top of each
  # runner's preparation therefore, not next to `docker run`.
  #
  # Ending the pause stays with the sweep (see Orchestration::UpdatePause):
  # a preparation that fails before any container exists leaves nothing in
  # flight, so the next tick thaws Watchtower on its own.
  def pause_updates!
    Orchestration::UpdatePause.pause!(self.class::UPDATE_PAUSE_REASON)
  end

  # Always pull — some runners point at floating tags (csv-importer is on
  # `:develop`), so a locally-cached image may be stale. `docker pull` is
  # cheap when the digest already matches (manifest check only), and the
  # cost is irrelevant compared to the user-initiated container run that
  # follows.
  def pull_image_if_needed!
    image = self.class::IMAGE
    ok, output = Orchestration::DockerCli.pull_image(image)
    return if ok

    raise Error, error(:image_pull_failed, output: output.strip)
  end

  # Docker accepts missing bind-mount sources (creates them as empty dirs
  # silently with `-v`, refuses with `--mount`) — predictable behavior
  # requires we create the HELIOS-owned ones ourselves up-front.
  def ensure_bind_mount_sources!
    FileUtils.mkdir_p(BackupRepository.directory) if BackupRepository.directory
    FileUtils.mkdir_p(self.class.runtime_directory)
    FileUtils.mkdir_p(self.class.influx_staging_directory)
  end

  # Drops the IN_PROGRESS_CACHE_TTL snapshot the moment the container is
  # live so the next /backups poll re-reads docker instead of trusting a
  # stale "no container yet" entry written during the S3 download phase.
  # Without this, an S3 restore briefly observes no Downloader (reset_state!
  # has run) and no container (stale cache) at once — long enough for
  # detect_completion! to fire prematurely and paint the card green.
  def run_container! # rubocop:disable Metrics/AbcSize
    ensure_bind_mount_sources!
    logger.info("docker run -d (image=#{self.class::IMAGE})")
    output, status = Open3.capture2e(*docker_run_command)
    logger.info("docker run success=#{status.success?} output=#{output.strip.inspect}")
    if status.success?
      self.class.invalidate_in_progress_cache!
      return
    end

    raise Error, error(:already_in_progress) if output.include?('is already in use')

    raise Error, error(:start_failed, output: output.strip)
  end

  # Localized error string from the subclass's i18n namespace
  # (backups.runner.errors.* or backups.restorer.errors.*).
  def error(key, **)
    I18n.t("#{self.class::I18N_SCOPE}.errors.#{key}", **)
  end
end
