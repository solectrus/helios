class BackupRepository
  # Filesystem-backed storage adapter (default destination). Backups live
  # under `${data_path}/helios/backups`, inside HELIOS's own bind mount —
  # every filesystem operation uses plain File IO.
  module Local
    class << self
      include BackupRepository::Tracking

      def directory
        ::File.join(Rails.configuration.data_path, 'helios', 'backups')
      end

      # Host-side equivalent of `directory` — bind-mount sources for the
      # docker runners must be host paths even when HELIOS itself sees a
      # different container-internal mount.
      def host_directory
        ::File.join(Orchestration::Runner.host_data_path, 'helios', 'backups')
      end

      def destination_configured?
        true
      end

      def destination_key
        'local'
      end

      def destination_coords
        {}
      end

      def record_backup!(filename)
        raise BackupRepository::NotFound unless BackupRepository.valid_filename?(filename)

        path = ::File.join(directory, filename)
        stat = ::File.stat(path)
        archive = BackupRepository.read_archive(path)
        upsert_backup_record(filename, stat.size, archive)
      rescue Errno::ENOENT
        nil
      end

      def read_archive_for(filename)
        BackupRepository.read_archive(::File.join(directory, filename))
      end

      # 64 KB chunks: keep multi-GB downloads streamed instead of buffered.
      def download(filename)
        raise BackupRepository::NotFound unless BackupRepository.valid_filename?(filename)

        ::File.open(::File.join(directory, filename), 'rb') do |file|
          while (chunk = file.read(64 * 1024))
            yield chunk
          end
        end
      rescue Errno::ENOENT
        raise BackupRepository::NotFound
      end

      def remove_files!(filenames)
        filenames.each do |filename|
          FileUtils.rm_f(::File.join(directory, filename))
        end
      end

      def read_error_file(filename = BackupRepository::ERROR_FILENAME)
        ::File.read(::File.join(directory, filename)).strip.presence
      rescue Errno::ENOENT
        nil
      end

      def remove_error_file!(filename = BackupRepository::ERROR_FILENAME)
        FileUtils.rm_f(::File.join(directory, filename))
      end
    end
  end
end
