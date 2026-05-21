class BackupRepository
  # Filesystem-backed storage adapter — the default destination. Backups live
  # under `${data_path}/helios/backups`, which is part of HELIOS's own bind
  # mount, so every filesystem operation uses plain File IO.
  #
  # Listing is served from the shared JSON index (BackupRepository::Index)
  # rather than re-reading tar headers on every visit. Stale detection is
  # cheap: compare the current `Dir.children` listing — name + size + mtime
  # — against the index. When nothing changed, the page renders without
  # touching the tar files at all; when something did change (a new tar
  # appeared, one was removed, one was overwritten), refresh! reads only
  # the affected archives.
  module Local
    class << self
      include BackupRepository::IndexedAdapter

      def directory
        ::File.join(Rails.configuration.data_path, 'helios', 'backups')
      end

      # Host-side equivalent of `directory`. Bind-mount sources for the docker
      # runners must be host paths even when HELIOS itself sees a different
      # container-internal mount.
      def host_directory
        ::File.join(Orchestration::Runner.host_data_path, 'helios', 'backups')
      end

      # Local backups always live in HELIOS's own mount, so the destination
      # is unconditionally available — the predicate exists only to satisfy
      # the IndexedAdapter contract shared with External/S3.
      def destination_configured?
        true
      end

      def destroy!(filename)
        raise BackupRepository::NotFound unless BackupRepository.valid_filename?(filename)

        path = ::File.join(directory, filename)
        raise BackupRepository::NotFound unless ::File.exist?(path)

        FileUtils.rm_f(path)
        FileUtils.rm_f("#{path}#{BackupRepository::LEGACY_MANIFEST_SUFFIX}")
        ensure_index_fresh!
        update_index { |index| index['backups'] = index['backups'].reject { |entry| entry['filename'] == filename } }
      end

      def clear_error!(filename = BackupRepository::ERROR_FILENAME)
        FileUtils.rm_f(::File.join(directory, filename))
        index_key = error_files[filename]
        return unless index_key

        update_index { |index| index[index_key] = nil }
      end

      def prune!(keep: BackupRepository::MAX_BACKUPS - 1)
        ensure_index_fresh!
        stale = read_index['backups'].drop(keep)
        return if stale.empty?

        stale.each do |entry|
          FileUtils.rm_f(::File.join(directory, entry['filename']))
          FileUtils.rm_f(::File.join(directory, "#{entry['filename']}#{BackupRepository::LEGACY_MANIFEST_SUFFIX}"))
        end
        update_index { |index| index['backups'] = index['backups'].first(keep) }
      end

      def read_archive_for(filename)
        BackupRepository.read_archive(::File.join(directory, filename))
      end

      # Streams the tar to a block in 64 KB chunks. The BackupsController wraps
      # this in an Enumerator-backed response_body so multi-GB downloads don't
      # buffer the whole archive in memory.
      def download(filename)
        raise BackupRepository::NotFound unless BackupRepository.valid_filename?(filename)

        path = ::File.join(directory, filename)
        raise BackupRepository::NotFound unless ::File.exist?(path)

        ::File.open(path, 'rb') do |file|
          while (chunk = file.read(64 * 1024))
            yield chunk
          end
        end
      end

      # No-op: the local adapter sees writes by the detached runner as soon
      # as the tar file lands in `directory`, so no pending marker is needed.
      # Accepts (and ignores) the expected-filename argument so the facade
      # can call `mark_pending!` uniformly across adapters.
      def mark_pending!(*); end

      # Rebuilds the index from the actual filesystem. Reuses cached entries
      # for tars that didn't change (name + size + mtime match), so a new
      # or overwritten backup only triggers a single tar read.
      # No-op: the local adapter sees writes by the detached runner as soon
      # as the tar file lands in `directory`, so there is no need for a
      # marker. Implemented so the facade can call `mark_pending!` without
      # branching on the active destination.
      def mark_pending!
        nil
      end

      def refresh!
        listing = scan_filesystem
        Index.write(
          'destination' => 'local',
          'updated_at' => Time.current.iso8601,
          'backups' => merge_with_cache(listing),
          'error_message' => read_text_file(BackupRepository::ERROR_FILENAME),
          'restore_error_message' => read_text_file(RestoreRunner::ERROR_FILENAME),
        )
      end

      private

      def ensure_index_fresh!
        refresh! unless cache_fresh?
      end

      # Cheap in-process scan to decide whether the cached index is still
      # accurate — about a millisecond for the five archives the runner
      # keeps around. Compares the listing tuple (name, size, mtime) so an
      # in-place rewrite of the same filename is also caught.
      def cache_fresh?
        index = Index.read
        return false unless index
        return false unless index['destination'] == 'local'
        return false unless index_complete?(index)

        current = scan_filesystem.map { |meta| [meta[:filename], meta[:bytes], meta[:mtime].iso8601] }
        cached = (index['backups'] || []).map { |entry| [entry['filename'], entry['bytes'], entry['mtime']] }
        current == cached
      end

      def read_index
        Index.read || { 'backups' => [], 'destination' => 'local',
                        'error_message' => nil, 'restore_error_message' => nil }
      end

      def update_index
        index = read_index
        yield index
        index['updated_at'] = Time.current.iso8601
        Index.write(index)
      end

      def scan_filesystem
        return [] unless Dir.exist?(directory)

        Dir.children(directory)
           .grep(BackupRepository::FILENAME_PATTERN)
           .map { |filename| build_meta(filename) }
           .sort_by { |meta| [meta[:mtime], meta[:filename]] }
           .reverse
      end

      def build_meta(filename)
        path = ::File.join(directory, filename)
        stat = ::File.stat(path)
        { filename: filename, bytes: stat.size, mtime: stat.mtime.in_time_zone }
      end

      def read_text_file(filename)
        ::File.read(::File.join(directory, filename)).strip.presence
      rescue Errno::ENOENT
        nil
      end
    end
  end
end
