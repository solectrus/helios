class BackupRepository
  # docker:cli-backed storage adapter for an external host mount (#105).
  #
  # All filesystem reads (listing, find, error_message) are served from a
  # JSON index next to helios/config.yaml — touching docker would otherwise
  # cost ~300 ms cold-start per call and turn the /backups page into a
  # noticeably slow render. Writes (destroy, prune, refresh) dispatch a
  # short-lived `docker:cli` sidecar that mounts the configured
  # `external_path` as `/data`, then update the index in place.
  #
  # The query/index half and the sidecar/refresh half are shared with the
  # other adapters via IndexedAdapter and SidecarAdapter; what remains here
  # is the docker:cli-specific IO — the bind-mount sidecar command, the
  # `tar`/`stat` scripts, and the path/cache plumbing.
  module External # rubocop:disable Metrics/ModuleLength
    IMAGE = BackupRunner::IMAGE
    LIST_GLOB = 'solectrus-backup-*.tar'.freeze

    class << self
      include BackupRepository::IndexedAdapter
      include BackupRepository::SidecarAdapter

      # HELIOS itself never sees the external path. Operations that need a
      # container-internal path (`mkdir_p`, etc.) must guard against this.
      def directory
        nil
      end

      # The configured host path used as the docker bind-mount source. Blank
      # when the user has not finished configuring an external destination —
      # callers should treat that as "no backups available".
      def host_directory
        Configuration.current.backup.external_path.presence
      end

      def destination_configured?
        host_directory.present?
      end

      def destroy!(filename)
        raise BackupRepository::NotFound unless BackupRepository.valid_filename?(filename)

        ensure_index_fresh!
        index = read_index
        raise BackupRepository::NotFound unless index['backups'].any? { |entry| entry['filename'] == filename }

        sidecar_run!('rm', '-f', "/data/#{filename}", "/data/#{filename}#{BackupRepository::LEGACY_MANIFEST_SUFFIX}")
        index['backups'] = index['backups'].reject { |entry| entry['filename'] == filename }
        write_index(index)
      end

      def clear_error!(filename = BackupRepository::ERROR_FILENAME)
        return unless host_directory

        sidecar_run!('rm', '-f', "/data/#{filename}")
        index_key = error_files[filename]
        return unless index_key

        index = read_index
        index[index_key] = nil
        write_index(index)
      end

      def prune!(keep: BackupRepository::MAX_BACKUPS - 1)
        ensure_index_fresh!
        index = read_index
        stale = index['backups'].drop(keep)
        return if stale.empty?

        args = stale.flat_map do |entry|
          ["/data/#{entry['filename']}",
           "/data/#{entry['filename']}#{BackupRepository::LEGACY_MANIFEST_SUFFIX}"]
        end
        sidecar_run!('rm', '-f', *args)
        index['backups'] = index['backups'].first(keep)
        write_index(index)
      end

      # Streams the tar to a block in 64 KB chunks. The BackupsController wraps
      # this in an Enumerator-backed response_body so multi-GB downloads don't
      # buffer the whole archive in memory — the docker:cli sidecar `cat`s the
      # tar straight from the external mount into the HTTP response.
      def download(filename, &)
        raise BackupRepository::NotFound unless downloadable?(filename)

        stream_sidecar_download('cat', sidecar_path(filename), &)
      end

      # Used by RestoreRunner for archive validation — pulls the live tar
      # through the sidecar so it can read config.yaml bytes that the index
      # does not cache. Not used by .all / .find!.
      def read_archive_for(filename)
        return BackupRepository::EMPTY_ARCHIVE unless host_directory

        stream_sidecar_archive('cat', "/data/#{filename}")
      end

      # Rebuilds the on-disk index from the actual external mount. One docker
      # run for the directory listing + error file, plus one per tar that
      # changed (size/mtime differ from the cached entry) to read the inner
      # file list and image versions. Stable visits (no new backups) end up
      # with one docker run, not N+1. Returns the parsed state on a real
      # rebuild, nil when it bailed (see below) — detect_completion! relies
      # on that to skip reconciliation after a failed refresh.
      def refresh!
        if host_directory.blank?
          Index.delete!
          return nil
        end

        result = fetch_state
        # A nil result means the sidecar itself could not run (docker daemon
        # down, image missing) — never "the mount is empty", since the
        # listing script exits 0 even with no backups. Keep the stale index
        # rather than wiping every cached backup off the page for a
        # transient outage.
        return nil if result.nil?

        Index.write(
          'destination' => 'external',
          'external_path' => host_directory,
          'updated_at' => Time.current.iso8601,
          'backups' => merge_with_cache(result[:listing]),
          'error_message' => result[:error_message],
          'restore_error_message' => result[:restore_error_message],
        )
        result
      end

      def pending_marker_path
        ::File.join(Rails.configuration.data_path, 'helios', 'external_backup_pending.flag')
      end

      private

      def in_progress_cache_key
        'helios_external_backup_in_progress'
      end

      def downloadable?(filename)
        return false unless BackupRepository.valid_filename?(filename)
        return false unless host_directory

        ensure_index_fresh!
        read_index['backups'].any? { |entry| entry['filename'] == filename }
      end

      # In-container path of a backup tar, rebuilt from the matched date/time
      # digits as integers. The result is therefore composed only of a
      # literal template and integers — it provably carries no path traversal
      # or shell metacharacters, regardless of what the caller passes in.
      def sidecar_path(filename)
        match = BackupRepository::FILENAME_PATTERN.match(filename.to_s)
        raise BackupRepository::NotFound unless match

        format('/data/solectrus-backup-%<date>08d-%<time>06d.tar', date: match[1].to_i, time: match[2].to_i)
      end

      def cache_fresh?
        index = Index.read
        return false unless index

        index['destination'] == 'external' &&
          index['external_path'] == host_directory &&
          index_complete?(index)
      end

      def read_index
        Index.read || { 'backups' => [], 'external_path' => host_directory,
                        'error_message' => nil, 'restore_error_message' => nil }
      end

      # The External adapter reads tar metadata through `tar -tvf`/`tar -xOf`
      # inside the sidecar (see metadata_script) rather than streaming the
      # whole archive across the docker socket, so it overrides the generic
      # read_archive_for-based build_entry from IndexedAdapter.
      def build_entry(meta)
        metadata = fetch_metadata(meta[:filename])
        images = BackupRepository.images_from_config(metadata[:config])
        {
          'filename' => meta[:filename],
          'bytes' => meta[:bytes],
          'mtime' => meta[:mtime].iso8601,
          'files' => metadata[:entries].map { |entry| { 'name' => entry[:name], 'bytes' => entry[:bytes] } },
          'influxdb_image' => images[:influxdb],
          'postgresql_image' => images[:postgresql],
        }
      end

      # Reads the entry list (header-only, no body bytes) plus the inner
      # helios/config.yaml from a single tar in one sidecar invocation. The
      # alternative — `cat <tar> | TarReader` over a non-rewindable pipe —
      # streams every body byte through the pipe because PipeIo cannot seek;
      # for a 500 MB InfluxDB backup that means moving the whole tar across
      # the docker socket just to find a 10 KB config file. `tar -tvf` and
      # `tar -xOf` read the archive locally inside the sidecar and emit
      # only the metadata we actually want.
      def fetch_metadata(filename)
        output, status = sidecar_capture('sh', '-c', metadata_script(filename))
        return { entries: [], config: nil } unless status.success?

        parse_metadata(output)
      end

      def metadata_script(filename)
        <<~SH
          tar -tvf /data/#{filename} | awk '$1 ~ /^-/ { printf "ENTRY|%s|%s\\n", $3, $NF }'
          echo CONFIG_BEGIN
          tar -xOf /data/#{filename} ./#{BackupRepository::CONFIG_ENTRY_PATH} 2>/dev/null || true
          echo CONFIG_END
        SH
      end

      def parse_metadata(output)
        entry_lines, config_lines = split_metadata_lines(output.each_line.map(&:chomp))
        {
          entries: entry_lines.filter_map { |line| parse_metadata_entry(line) },
          config: config_lines&.any? ? BackupRepository.parse_config_yaml(config_lines.join("\n")) : nil,
        }
      end

      def split_metadata_lines(lines)
        entry_lines = []
        config_lines = nil

        lines.each do |line|
          break if line == 'CONFIG_END'

          if line == 'CONFIG_BEGIN'
            config_lines = []
          elsif config_lines
            config_lines << line
          elsif line.start_with?('ENTRY|')
            entry_lines << line
          end
        end

        [entry_lines, config_lines]
      end

      def parse_metadata_entry(line)
        _prefix, size, name = line.split('|', 3)
        return nil if name.blank? || size.blank?

        { name: name.delete_prefix('./'), bytes: size.to_i }
      end

      def state_script
        error_blocks = error_files.map { |filename, key| error_block_script(filename, key) }.join
        <<~SH
          for f in /data/#{LIST_GLOB}; do
            [ -f "$f" ] || continue
            stat -c "BACKUP|%n|%s|%Y" "$f"
          done
          #{error_blocks}
        SH
      end

      def error_block_script(filename, key)
        marker = key.upcase
        <<~SH
          if [ -f /data/#{filename} ]; then
            echo "#{marker}_BEGIN"
            cat /data/#{filename}
            echo "#{marker}_END"
          fi
        SH
      end

      def parse_listing_line(line)
        _prefix, path, size, mtime = line.split('|', 4)
        return nil if path.nil? || size.nil? || mtime.nil?

        filename = ::File.basename(path)
        return nil unless BackupRepository.valid_filename?(filename)

        { filename: filename, bytes: size.to_i, mtime: Time.zone.at(mtime.to_i) }
      end

      # `docker:cli` ships with `docker` as its default entrypoint, so
      # `docker run docker:cli rm /data/foo` would invoke `docker rm` against
      # the Docker API rather than the busybox `rm` we want. Pull the binary
      # out of the args and pass it as `--entrypoint` so the rest of `cmd`
      # becomes its arguments.
      def sidecar_command(*cmd)
        entrypoint, *args = cmd
        ['docker', 'run', '--rm', '-v', "#{host_directory}:/data",
         '--entrypoint', entrypoint, IMAGE, *args]
      end
    end
  end
end
