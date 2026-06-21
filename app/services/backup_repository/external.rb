class BackupRepository
  # docker:cli-backed adapter for an external host mount (#105). Listing
  # is served from SQLite; mutating ops dispatch a short-lived sidecar
  # that mounts the configured `external_path` as `/data`.
  module External
    IMAGE = BackupRunner::IMAGE

    class << self
      include BackupRepository::Tracking
      include BackupRepository::Sidecar

      def directory
        nil
      end

      def host_directory
        Configuration.current.backup.external_path.presence
      end

      def destination_configured?
        host_directory.present?
      end

      def destination_key
        'external'
      end

      def destination_coords
        { external_path: host_directory }
      end

      def record_backup!(filename)
        raise BackupRepository::NotFound unless BackupRepository.valid_filename?(filename)
        return nil unless destination_configured?

        metadata = fetch_metadata(filename)
        return nil unless metadata && metadata[:bytes]

        entries = metadata[:entries].map { |e| BackupRepository::Entry.new(name: e[:name], bytes: e[:bytes]) }
        archive = BackupRepository::ArchiveContents.new(entries: entries, config: metadata[:config])
        upsert_backup_record(filename, metadata[:bytes], archive)
      end

      def download(filename, &)
        raise BackupRepository::NotFound unless BackupRepository.valid_filename?(filename)
        raise BackupRepository::NotFound unless host_directory
        raise BackupRepository::NotFound unless recorded?(filename)

        stream_sidecar_download('cat', sidecar_path(filename), &)
      end

      # An external bind mount is not reachable from the browser; downloads
      # must go through the sidecar stream.
      def direct_download_url(_filename)
        nil
      end

      def read_archive_for(filename)
        return BackupRepository::EMPTY_ARCHIVE unless host_directory

        stream_sidecar_archive('cat', "/data/#{filename}")
      end

      def remove_files!(filenames)
        return if filenames.empty?
        return unless host_directory

        args = filenames.map { |filename| "/data/#{filename}" }
        sidecar_run!('rm', '-f', *args)
      end

      private

      # In-container path rebuilt from the matched date/time digits as
      # integers so the value provably carries no path traversal or shell
      # metacharacters regardless of the caller.
      def sidecar_path(filename)
        match = BackupRepository::FILENAME_PATTERN.match(filename.to_s)
        raise BackupRepository::NotFound unless match

        format('/data/solectrus-backup-%<date>08d-%<time>06d.tar', date: match[1].to_i, time: match[2].to_i)
      end

      # One sidecar invocation that emits size + entry list + inner
      # helios/config.yaml. Avoids streaming the whole archive over the
      # docker socket just to read 10 KB of config.
      def fetch_metadata(filename)
        output, status = sidecar_capture('sh', '-c', metadata_script(filename))
        return nil unless status.success?

        parse_metadata(output)
      end

      def metadata_script(filename)
        <<~SH
          stat -c "SIZE|%s" /data/#{filename} 2>/dev/null
          tar -tvf /data/#{filename} | awk '$1 ~ /^-/ { printf "ENTRY|%s|%s\\n", $3, $NF }'
          echo CONFIG_BEGIN
          tar -xOf /data/#{filename} ./#{BackupRepository::CONFIG_ENTRY_PATH} 2>/dev/null || true
          echo CONFIG_END
        SH
      end

      def parse_metadata(output)
        bytes, entry_lines, config_lines = split_metadata_lines(output.each_line.map(&:chomp))
        {
          bytes: bytes,
          entries: entry_lines.filter_map { |line| parse_metadata_entry(line) },
          config: config_lines&.any? ? BackupRepository.parse_config_yaml(config_lines.join("\n")) : nil,
        }
      end

      def split_metadata_lines(lines) # rubocop:disable Metrics/MethodLength
        bytes = nil
        entry_lines = []
        config_lines = nil

        lines.each do |line|
          break if line == 'CONFIG_END'

          if line.start_with?('SIZE|')
            bytes = line.delete_prefix('SIZE|').to_i
          elsif line == 'CONFIG_BEGIN'
            config_lines = []
          elsif config_lines
            config_lines << line
          elsif line.start_with?('ENTRY|')
            entry_lines << line
          end
        end

        [bytes, entry_lines, config_lines]
      end

      def parse_metadata_entry(line)
        _prefix, size, name = line.split('|', 3)
        return nil if name.blank? || size.blank?

        { name: name.delete_prefix('./'), bytes: size.to_i }
      end

      # `docker:cli` ships with `docker` as its default entrypoint, so
      # `docker run docker:cli rm /data/foo` would invoke `docker rm`
      # against the Docker API rather than the busybox `rm` we want.
      #
      # `--mount type=bind` (not `-v`) refuses to start the sidecar when
      # the external mount source has vanished, instead of fabricating an
      # empty `/data` and silently returning bogus results (an empty
      # listing, "delete succeeded" on a non-existent file, …).
      def sidecar_command(*cmd)
        entrypoint, *args = cmd
        ['docker', 'run', '--rm',
         '--mount', "type=bind,source=#{host_directory},target=/data",
         '--entrypoint', entrypoint, IMAGE, *args]
      end
    end
  end
end
