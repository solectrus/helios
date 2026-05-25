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
  module Tracking
    def all
      return Backup.none unless destination_configured?

      Backup.for_destination(destination_key, **destination_coords).newest_first
    end

    def find!(filename)
      fetch_record!(filename)
    end

    def destroy!(filename)
      record = fetch_record!(filename)
      remove_files!([filename])
      record.destroy!
    end

    def prune!(keep: BackupRepository::MAX_BACKUPS - 1)
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

    def runtime_error_path(filename)
      ::File.join(DetachedRunner.runtime_directory, filename)
    end

    # Detects the moment a detached BackupRunner/RestoreRunner finished
    # and persists what it left behind: error.txt → RunnerLog, fresh tar
    # → Backup. Triggered by either a live in_progress observation
    # (Rails.cache marker) or the pending-marker file from start.
    def detect_completion!
      current = BackupRunner.in_progress&.filename || RestoreRunner.in_progress&.filename

      if current
        Rails.cache.write(in_progress_cache_key, current, expires_in: 1.hour)
        return
      end

      return unless Rails.cache.read(in_progress_cache_key) || pending_refresh?

      Rails.cache.delete(in_progress_cache_key)
      process_completion!(pending_marker_content)
      clear_pending!
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
      ::File.read(pending_marker_path).strip.presence
    rescue Errno::ENOENT
      nil
    end

    def process_completion!(expected_filename)
      capture_error!(:restore, RestoreRunner::ERROR_FILENAME)
      return if capture_error!(:backup, BackupRepository::ERROR_FILENAME)

      return if expected_filename.blank?
      return if record_backup!(expected_filename)

      # A detached backup that died without writing error.txt (OOM, host
      # crash) leaves neither a tar nor an error file — record an
      # "incomplete" message so the run is visibly surfaced as a failure.
      RunnerLog.record_error!(:backup, I18n.t('backups.runner.errors.incomplete'))
    end

    # Returns truthy when an error file was found, so process_completion!
    # can branch on the backup error and stop before record_backup!.
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
  end
end
