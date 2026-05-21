require 'open3'

class BackupRepository
  # Sidecar-and-index-refresh layer shared by the External and S3 adapters.
  # Both serve /backups from the JSON index and rebuild it through a
  # short-lived docker sidecar; this module holds everything around that
  # which is identical between them — the framed-output parser, the
  # detached-run completion detection, and the sidecar invocation helpers.
  #
  # Including adapters must provide: `cache_fresh?`, `refresh!`,
  # `state_script`, `parse_listing_line`, `sidecar_command`,
  # `in_progress_cache_key`, `pending_marker_path` and
  # `destination_configured?`.
  module SidecarAdapter # rubocop:disable Metrics/ModuleLength
    # Detects the moment a detached BackupRunner finished — the sidecar
    # writes the tar without HELIOS knowing, so the index has to be rebuilt
    # once `in_progress` transitions back to nil. Two trigger sources:
    #
    #   * a Rails.cache marker, set whenever a visit observed `in_progress`
    #     (works while the user is watching /backups during the run);
    #   * a pending-marker file dropped by `BackupRunner.start`, so the
    #     refresh still happens if /backups is never opened during the run.
    def detect_completion!
      current = BackupRunner.in_progress&.filename
      previous = Rails.cache.read(in_progress_cache_key)

      if current
        Rails.cache.write(in_progress_cache_key, current, expires_in: 1.hour)
      elsif previous || pending_refresh?
        Rails.cache.delete(in_progress_cache_key)
        expected_backup = pending_marker_content
        reconcile_missing_backup!(expected_backup) if refresh!
        clear_pending!
      end
    end

    # Drops a marker so the next visit's detect_completion! rebuilds the
    # index even if /backups is never opened during the run. For a backup
    # the marker also carries the expected tar filename, so a run that
    # dies without writing error.txt (OOM, host crash) can still be
    # reported as failed instead of vanishing — see reconcile_missing_backup!.
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

    private

    def ensure_index_fresh!
      detect_completion!
      refresh! unless cache_fresh?
    end

    def pending_marker_content
      ::File.read(pending_marker_path).strip.presence
    rescue Errno::ENOENT
      nil
    end

    # A detached backup that died without writing error.txt (OOM-killed,
    # host crash) leaves neither a tar nor an error file — without this the
    # run would silently vanish from /backups. When the pending marker
    # named an expected tar that the freshly-refreshed index still does not
    # contain, and no error was captured either, record a generic failure
    # so the user is told the backup did not complete.
    def reconcile_missing_backup!(expected_filename)
      return if expected_filename.blank?

      index = Index.read
      return unless index
      return if index['error_message'].present?
      return if Array(index['backups']).any? { |entry| entry['filename'] == expected_filename }

      Index.write(index.merge('error_message' => I18n.t('backups.runner.errors.incomplete')))
    end

    def write_index(index)
      Index.write(index.merge('updated_at' => Time.current.iso8601))
    end

    # One sidecar invocation returning the directory listing plus the
    # backup and restore error files in a single round trip. Output:
    #
    #   BACKUP|<path>|<bytes>|<mtime>
    #   ...
    #   <KEY>_BEGIN
    #   <error text>
    #   <KEY>_END
    #
    # where <KEY> is one of ERROR_FILES.values (e.g. ERROR_MESSAGE).
    def fetch_state
      output, status = sidecar_capture('sh', '-c', state_script)
      return nil unless status.success?

      parse_state(output)
    end

    def parse_state(output)
      listing, errors = collect_listing_and_errors(output)
      listing.sort_by! { |meta| [meta[:mtime], meta[:filename]] }
      listing.reverse!
      {
        listing: listing,
        error_message: errors[error_files[BackupRepository::ERROR_FILENAME]],
        restore_error_message: errors[error_files[RestoreRunner::ERROR_FILENAME]],
      }
    end

    def collect_listing_and_errors(output)
      listing = []
      errors = {}
      current_key = nil
      current_lines = nil

      output.each_line do |line|
        line = line.chomp
        if (match = line.match(/\A(.+)_(BEGIN|END)\z/))
          current_key, current_lines = handle_error_marker(errors, current_key, current_lines, match[1], match[2])
        elsif current_lines
          current_lines << line
        else
          append_listing_line(listing, line)
        end
      end

      [listing, errors]
    end

    # Tracks the open/close pair for each `<KEY>_BEGIN ... <KEY>_END` block
    # the sidecar emits — returns the new "currently reading" state for the
    # caller to keep iterating with.
    def handle_error_marker(errors, current_key, current_lines, marker_key, kind)
      key = marker_key.downcase
      if kind == 'BEGIN' && error_files.value?(key)
        [key, []]
      elsif kind == 'END' && current_key == key
        errors[key] = current_lines.join("\n").strip.presence
        [nil, nil]
      else
        [current_key, current_lines]
      end
    end

    def append_listing_line(listing, line)
      return unless line.start_with?('BACKUP|')

      meta = parse_listing_line(line)
      listing << meta if meta
    end

    def sidecar_run(*cmd)
      Open3.capture2e(*sidecar_command(*cmd))
    end

    # Like sidecar_run, but raises BackupRepository::Error on a non-zero
    # exit — mutating operations must not update the cached index after the
    # actual rm/cp silently failed.
    def sidecar_run!(*cmd)
      output, status = sidecar_run(*cmd)
      return output if status.success?

      message = output.to_s.strip.presence || "exited with status #{status.exitstatus}"
      Rails.logger.error("#{name} sidecar failed: #{cmd.inspect} — #{message}")
      raise BackupRepository::Error, message
    end

    def sidecar_capture(*cmd)
      Open3.capture2(*sidecar_command(*cmd))
    end

    # Runs a sidecar whose stdout is a tar stream and parses it into an
    # ArchiveContents. Uses `popen2`, not `popen2e`, on purpose: the stdout
    # is a binary tar — merging stderr into it would corrupt the archive.
    # With `popen2` the sidecar's stderr passes straight through to HELIOS's
    # own stderr/log instead.
    #
    # Every failure mode is logged and yields an empty archive: a non-zero
    # exit, an unreadable tar, a sidecar that could not launch, and — the
    # subtle one — a clean exit that nonetheless produced no entries (an S3
    # object not yet readable in the moments right after upload). The caller
    # treats an empty archive as a stale index entry and retries later.
    def stream_sidecar_archive(*cmd)
      Open3.popen2(*sidecar_command(*cmd)) do |_in, out, wait|
        out.binmode
        archive = BackupRepository.parse_tar_stream(BackupRepository::PipeIo.new(out))
        # Drain anything left over so the wait status reflects a clean exit
        # — TarReader stops as soon as it sees the zero-block sentinel.
        out.read
        verified_archive(archive, wait.value, cmd)
      end
    rescue Gem::Package::TarInvalidError => e
      warn_archive("produced an unreadable tar (#{e.message})", cmd)
    rescue Errno::ENOENT => e
      warn_archive("could not be launched (#{e.message})", cmd)
    end

    # A non-zero exit yields an empty archive. A clean exit with zero
    # entries is still returned as-is, but logged: it is the trace of an S3
    # object not yet readable in the moments right after upload.
    def verified_archive(archive, status, cmd)
      return warn_archive("exited #{status.exitstatus}", cmd) unless status.success?

      warn_archive('produced no tar entries', cmd) if archive.entries.empty?
      archive
    end

    def warn_archive(reason, cmd)
      Rails.logger.warn("#{name}: archive sidecar #{reason} — #{cmd.inspect}")
      BackupRepository::EMPTY_ARCHIVE
    end

    # Runs a sidecar whose stdout is a tar stream and yields it to the block
    # in 64 KB chunks (HTTP download). `popen2` keeps stderr off the stdout
    # pipe so a docker/aws-cli warning can never end up inside the download;
    # a non-zero exit raises BackupRepository::Error.
    def stream_sidecar_download(*cmd)
      Open3.popen2(*sidecar_command(*cmd)) do |_in, out, wait|
        out.binmode
        while (chunk = out.read(64 * 1024))
          yield chunk
        end
        status = wait.value
        next if status.success?

        raise BackupRepository::Error, "sidecar exited with status #{status.exitstatus}"
      end
    end
  end
end
