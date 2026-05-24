require 'aws-sdk-s3'

class BackupRepository
  # aws-sdk-s3-backed adapter for S3 and S3-compatible object stores (MinIO,
  # Backblaze B2, Wasabi …) via an optional `endpoint_url`. New tars are
  # downloaded once into a local staging dir to parse them locally;
  # backup.sh writes the same staging dir before uploading.
  module S3 # rubocop:disable Metrics/ModuleLength
    STAGING_DIRNAME = 'backups-staging'.freeze

    # Switch to multipart at 50 MB. AWS's default is 100 MB, but on Raspi
    # the smaller chunks let the progress bar move sooner and keep memory
    # use predictable on flaky home uplinks.
    MULTIPART_THRESHOLD = 50 * 1024 * 1024

    # Two parallel parts is the sweet spot for the typical home upstream:
    # one part keeps the pipe full, a second one absorbs TCP slow start
    # for the next chunk while the first is committing.
    UPLOAD_THREAD_COUNT = 2

    class << self
      include BackupRepository::Tracking

      # Container-internal staging path. Returned even when the
      # destination is not yet configured so callers that mkdir up front
      # don't have to branch on configuration state.
      def directory
        ::File.join(Rails.configuration.data_path, 'helios', STAGING_DIRNAME)
      end

      # Host-side staging directory used as the bind-mount source for
      # backup.sh's `/output`. Nil when the destination is not fully
      # configured so BackupRunner.unavailable_reason can surface it.
      def host_directory
        return nil unless destination_configured?

        ::File.join(Orchestration::Runner.host_data_path, 'helios', STAGING_DIRNAME)
      end

      def destination_configured?
        backup = Configuration.current.backup
        backup.aws_bucket.present? &&
          backup.aws_access_key_id.present? &&
          backup.aws_secret_access_key.present? &&
          backup.aws_region.present?
      end

      def destination_key
        's3'
      end

      def destination_coords
        { s3_endpoint_url: endpoint_url, s3_bucket: bucket, s3_prefix: prefix }
      end

      def record_backup!(filename) # rubocop:disable Metrics/MethodLength,Metrics/AbcSize
        raise BackupRepository::NotFound unless BackupRepository.valid_filename?(filename)
        return nil unless destination_configured?

        # Uploader thread may have already recorded the row from the
        # local copy; skip the S3 round-trip in that case.
        return scoped_records.find_by(filename: filename) if recorded?(filename)

        FileUtils.mkdir_p(directory)
        path = staging_path(filename)
        begin
          download_to_staging!(filename)
          return nil unless ::File.exist?(path)

          stat = ::File.stat(path)
          archive = BackupRepository.read_archive(path)
          upsert_backup_record(filename, stat.size, archive)
        rescue BackupRepository::Error => e
          Rails.logger.warn("#{name}: record_backup! download failed for #{filename} — #{e.message}")
          nil
        ensure
          FileUtils.rm_f(path)
        end
      end

      def download(filename, &)
        raise BackupRepository::NotFound unless BackupRepository.valid_filename?(filename)
        raise BackupRepository::NotFound unless destination_configured?
        raise BackupRepository::NotFound unless recorded?(filename)

        stream_object(object_key(filename), &)
      rescue Aws::S3::Errors::NoSuchKey
        raise BackupRepository::NotFound
      end

      # Reads the archive from the local staging copy that the Downloader
      # (or BackupRunner) leaves behind. RestoreRunner is the only caller
      # and now always invokes this after the download — buffering the
      # tar in RAM is therefore neither needed nor desirable.
      def read_archive_for(filename)
        return BackupRepository::EMPTY_ARCHIVE unless destination_configured?

        path = staging_path(filename)
        return BackupRepository::EMPTY_ARCHIVE unless ::File.exist?(path)

        BackupRepository.read_archive(path)
      end

      def remove_files!(filenames)
        return if filenames.empty?
        return unless destination_configured?

        keys = filenames.map { |name| object_key(name) }
        delete_keys!(keys, ignore_missing: true)
      end

      # Error files are written by backup.sh / restore.sh into the local
      # staging dir (the bind-mounted /output) and never reach S3 — only
      # successful tars are uploaded. read/remove therefore touch the
      # local filesystem, not the remote bucket.
      def read_error_file(filename = BackupRepository::ERROR_FILENAME)
        path = staging_path(filename)
        return nil unless ::File.exist?(path)

        ::File.read(path).strip.presence
      end

      def remove_error_file!(filename = BackupRepository::ERROR_FILENAME)
        FileUtils.rm_f(staging_path(filename))
      end

      # Multipart uploads aborted mid-flight are cleaned up by the SDK
      # before the error propagates, so retries don't leak partials.
      def upload_from_staging!(filename, progress_callback: nil)
        path = staging_path(filename)
        raise BackupRepository::Error, "staged tar missing: #{filename}" unless ::File.exist?(path)

        bridge = progress_bridge(progress_callback)
        transfer_manager.upload_file(
          path,
          bucket: bucket,
          key: object_key(filename),
          multipart_threshold: MULTIPART_THRESHOLD,
          thread_count: UPLOAD_THREAD_COUNT,
          progress_callback: bridge,
        )
      rescue Aws::S3::Errors::ServiceError, Seahorse::Client::NetworkingError => e
        raise BackupRepository::Error, "#{e.class}: #{e.message}"
      end

      def transfer_manager
        Aws::S3::TransferManager.new(client: client)
      end

      # Records a freshly-uploaded tar in the DB straight from the staged
      # copy — avoids the round-trip of re-downloading what we just
      # uploaded. Used by Uploader after upload_from_staging! completes;
      # for detached/resumed paths where no local copy exists any more,
      # `record_backup!` re-downloads from S3 instead.
      def record_from_staging!(filename)
        raise BackupRepository::NotFound unless BackupRepository.valid_filename?(filename)

        path = staging_path(filename)
        return nil unless ::File.exist?(path)

        stat = ::File.stat(path)
        archive = BackupRepository.read_archive(path)
        upsert_backup_record(filename, stat.size, archive)
      end

      def staging_path(filename)
        ::File.join(directory, filename)
      end

      def staged_tar_exists?(filename)
        ::File.exist?(staging_path(filename))
      end

      # Streams the tar from S3 into the local staging dir. The caller
      # should pass `total:` (from Backup#bytes) when known — some
      # S3-compatible endpoints (e.g. MinIO behind a reverse proxy that
      # only whitelists GET/PUT) forbid HEAD while allowing GET, so a
      # fallback head_object would break restore there.
      def download_to_staging!(filename, progress_callback: nil, total: nil)
        path = staging_path(filename)
        key = object_key(filename)
        downloaded = 0

        FileUtils.mkdir_p(directory)
        ::File.open(path, 'wb') do |io|
          stream_object(key) do |chunk|
            io.write(chunk)
            next unless progress_callback

            downloaded += chunk.bytesize
            progress_callback.call(downloaded, total)
          end
        end
      rescue Aws::S3::Errors::ServiceError, Seahorse::Client::NetworkingError => e
        FileUtils.rm_f(path)
        raise BackupRepository::Error, "#{e.class}: #{e.message}"
      end

      def bucket
        Configuration.current.backup.aws_bucket.to_s
      end

      def prefix
        normalize_prefix(Configuration.current.backup.s3_prefix)
      end

      # Shared with Backups::ConnectionTest so the probe targets the exact
      # prefix the live adapter writes to.
      def normalize_prefix(value)
        value.to_s.strip.gsub(%r{\A/+|/+\z}, '')
      end

      def endpoint_url
        Configuration.current.backup.s3_endpoint_url.to_s.strip.presence
      end

      # Builds a fresh Aws::S3::Client for every call so a config change
      # (new credentials, switched endpoint) is picked up without a restart.
      def client
        backup = Configuration.current.backup
        ClientFactory.build(
          access_key_id: backup.aws_access_key_id,
          secret_access_key: backup.aws_secret_access_key,
          region: backup.aws_region,
          endpoint: backup.s3_endpoint_url,
        )
      end

      # Writes a runner-style error file into the local staging dir so
      # detect_completion! surfaces the failure to the user. Used by the
      # Uploader (backup error) and Downloader (restore error) on top of
      # what backup.sh / restore.sh themselves write into the same dir.
      def write_error_file!(filename, message)
        FileUtils.mkdir_p(directory)
        ::File.write(::File.join(directory, filename), message)
      end

      private

      def object_key(filename)
        [prefix.presence, filename].compact.join('/')
      end

      # Translates the TransferManager's (bytes_per_part_array, totals_array)
      # callback into the simpler (bytes_uploaded, bytes_total) shape the
      # Uploader stores — UI code shouldn't need to know about the
      # part-array layout.
      def progress_bridge(progress_callback)
        return nil unless progress_callback

        lambda do |bytes_per_part, totals_per_part|
          progress_callback.call(Array(bytes_per_part).sum, Array(totals_per_part).sum)
        end
      end

      # Streams an S3 object to the given block in 64 KB chunks. Uses the
      # SDK's block form which writes each network chunk straight to the
      # block — no full-object buffering.
      def stream_object(key, &)
        client.get_object(bucket: bucket, key: key, &)
      end

      def delete_keys!(keys, ignore_missing: false)
        return if keys.empty?

        # delete_objects accepts up to 1000 keys per request; backup
        # batches stay well below that.
        client.delete_objects(
          bucket: bucket,
          delete: { objects: keys.map { |k| { key: k } }, quiet: true },
        )
      rescue Aws::S3::Errors::NoSuchKey
        raise unless ignore_missing
      rescue Aws::S3::Errors::ServiceError => e
        raise BackupRepository::Error, "#{e.class}: #{e.message}"
      end
    end
  end
end
