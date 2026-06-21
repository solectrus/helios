class BackupRepository
  # Shared DB-tracking layer for every adapter: listing, completion
  # detection, prune/destroy, and runner-error capture. Per-adapter IO
  # (deleting tars, reading error files, fetching tar metadata) is
  # supplied by Local/External/S3.
  #
  # Adapters must provide: `destination_key`, `destination_coords`,
  # `destination_configured?`, `remove_files!(filenames)`,
  # `record_backup!(filename)`.
  #
  # Error-file IO is destination-independent: backup.sh / restore.sh write
  # error.txt into the HELIOS-local runtime dir (see the comment in those
  # scripts), so all adapters share the same read/remove implementation
  # provided here.
  module Tracking # rubocop:disable Metrics/ModuleLength
    include Loggable

    # How often reading a freshly written tar is retried before HELIOS gives
    # up and marks the run incomplete. Guards against a backup that genuinely
    # produced no tar (host crash, no error file) being probed on every tick
    # forever, while still surviving a transient NAS/docker hiccup.
    RECORDING_MAX_ATTEMPTS = 10

    def all
      return Backup.none unless destination_configured?

      Backup.for_destination(destination_key, **destination_coords).newest_first
    end

    def latest
      all.first
    end

    def find!(filename)
      fetch_record!(filename)
    end

    def destroy!(filename)
      record = fetch_record!(filename)
      remove_files!([filename])
      record.destroy!
    end

    def prune!(keep: BackupRepository::MAX_BACKUPS)
      return unless destination_configured?

      stale = scoped_records.newest_first.offset(keep).to_a
      return if stale.empty?

      remove_files!(stale.map(&:filename))
      Backup.where(id: stale.map(&:id)).delete_all
    end

    def clear_error!(filename = BackupRepository::ERROR_FILENAME)
      remove_error_file!(filename)
      RunnerLog.clear!(RunnerLog.kind_for(filename))
    end

    def read_error_file(filename = BackupRepository::ERROR_FILENAME)
      ::File.read(runtime_error_path(filename)).strip.presence
    rescue Errno::ENOENT
      nil
    end

    def remove_error_file!(filename = BackupRepository::ERROR_FILENAME)
      FileUtils.rm_f(runtime_error_path(filename))
    end

    # Mirrors backup.sh's failure contract from the Ruby side (e.g. when the
    # BackupRunner preparing thread fails before the sidecar exists): write
    # the message into the same runtime error.txt that detect_completion!
    # later turns into a red completion card.
    def write_error_file!(message, filename = BackupRepository::ERROR_FILENAME)
      path = runtime_error_path(filename)
      FileUtils.mkdir_p(::File.dirname(path))
      ::File.write(path, message)
    end

    def runtime_error_path(filename)
      ::File.join(DetachedRunner.runtime_directory, filename)
    end

    # Detects the moment a detached BackupRunner/RestoreRunner finished
    # and persists what it left behind: error.txt → RunnerLog, fresh tar
    # → Backup. Triggered by either a live in_progress observation
    # (Rails.cache marker) or the pending-marker file from start.
    def detect_completion! # rubocop:disable Metrics/MethodLength,Metrics/AbcSize
      backup_ip = BackupRunner.in_progress
      restore_ip = RestoreRunner.in_progress
      current = backup_ip&.filename || restore_ip&.filename

      if current
        Rails.cache.write(in_progress_cache_key, current, expires_in: 1.hour)
        return
      end

      cached = Rails.cache.read(in_progress_cache_key)
      pending = pending_refresh?
      return unless cached || pending

      logger.info(
        "[detect_completion!] firing — backup_ip=#{backup_ip.inspect} restore_ip=#{restore_ip.inspect} " \
        "cached=#{cached.inspect} pending=#{pending} marker=#{pending_marker_content.inspect}",
      )
      Rails.cache.delete(in_progress_cache_key)
      process_completion!(pending_marker_content)
    end

    # The expected filename argument lets process_completion! report a
    # "ran but never produced a tar" failure even if backup.sh died
    # without writing error.txt (OOM, host crash).
    def mark_pending!(expected_filename = nil)
      return unless destination_configured?

      FileUtils.mkdir_p(::File.dirname(pending_marker_path))
      ::File.write(pending_marker_path, expected_filename.to_s)
    end

    def pending_refresh?
      ::File.exist?(pending_marker_path)
    end

    def clear_pending!
      FileUtils.rm_f(pending_marker_path)
    end

    def pending_marker_path
      ::File.join(Rails.configuration.data_path, 'helios', "#{destination_key}_backup_pending.flag")
    end

    # Filename recorded in the pending marker, or nil. Public hook used by
    # BackupRunner.in_progress to detect a tar that needs re-uploading
    # after a HELIOS restart.
    def pending_filename
      pending_marker_content
    end

    private

    def fetch_record!(filename)
      raise BackupRepository::NotFound unless BackupRepository.valid_filename?(filename)
      raise BackupRepository::NotFound unless destination_configured?

      scoped_records.find_by(filename: filename) || raise(BackupRepository::NotFound)
    end

    def scoped_records
      Backup.for_destination(destination_key, **destination_coords)
    end

    def recorded?(filename)
      scoped_records.exists?(filename: filename)
    end

    def in_progress_cache_key
      "helios_#{destination_key}_backup_in_progress"
    end

    def pending_marker_content
      parse_pending_marker.first
    end

    # Parses the two-line pending marker into [filename, attempts]: the first
    # line is the planned filename, the optional second line the recording
    # retry counter (see bump_pending_attempts!). Returns [nil, 0] when the
    # marker is missing.
    def parse_pending_marker
      filename, attempts = ::File.readlines(pending_marker_path, chomp: true)
      [filename.presence, attempts.to_i]
    rescue Errno::ENOENT
      [nil, 0]
    end

    # `expected_filename` is BackupRunner.start's planned tar name, blank
    # from RestoreRunner.start — disambiguates backup vs restore on a clean
    # exit (no error file).
    def process_completion!(expected_filename) # rubocop:disable Metrics/MethodLength
      restore_err = read_error_file(RestoreRunner::ERROR_FILENAME)
      backup_err = read_error_file(BackupRepository::ERROR_FILENAME)
      logger.info(
        "[process_completion!] expected=#{expected_filename.inspect} " \
        "restore_err=#{restore_err.inspect} backup_err=#{backup_err.inspect}",
      )
      restore_failed = capture_error!(:restore, RestoreRunner::ERROR_FILENAME)
      backup_failed = capture_error!(:backup, BackupRepository::ERROR_FILENAME)

      kind =
        if backup_failed
          :backup
        elsif restore_failed || expected_filename.blank?
          :restore
        elsif record_backup!(expected_filename)
          # S3 uploader prunes earlier (so :pruning phase is visible); this
          # second call is a no-op in that path and handles every other adapter.
          prune!
          :backup
        elsif bump_pending_attempts!(expected_filename) < RECORDING_MAX_ATTEMPTS
          # Clean exit but the freshly written tar isn't readable yet — a
          # transient NAS/docker hiccup. Keep the marker so the next scheduler
          # tick retries, instead of losing the backup for good.
          return
        else
          # Gave up: the tar never appeared (OOM, host crash, no error file).
          RunnerLog.record_error!(:backup, I18n.t('backups.runner.errors.incomplete'))
          :backup
        end

      RunnerLog.record_finished!(kind)
      clear_pending!
    end

    def capture_error!(kind, filename) # rubocop:disable Naming/PredicateMethod
      message = read_error_file(filename)
      return false if message.blank?

      RunnerLog.record_error!(kind, message)
      remove_error_file!(filename)
      true
    end

    def upsert_backup_record(filename, bytes, archive)
      images = BackupRepository.images_from_config(archive.config)
      record = Backup.find_or_initialize_by(destination: destination_key, filename: filename,
                                            **destination_coords)
      record.assign_attributes(
        bytes: bytes,
        created_at: BackupRepository.created_at_from(filename) || Time.current,
        influxdb_image: images[:influxdb],
        postgresql_image: images[:postgresql],
        files: BackupRepository.summarize_entries(archive.entries),
      )
      record.save!
      record
    end

    # Bumps and returns the recording retry counter, persisted as the marker's
    # second line so it survives a HELIOS restart. Lets a transient failure to
    # read a finished tar be retried on later ticks instead of dropped.
    def bump_pending_attempts!(filename)
      attempts = parse_pending_marker.last + 1
      ::File.write(pending_marker_path, "#{filename}\n#{attempts}")
      attempts
    end
  end
end
