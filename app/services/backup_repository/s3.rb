require 'shellwords'
require 'open3'

class BackupRepository
  # aws-cli-backed adapter for S3 and S3-compatible object stores (MinIO,
  # Backblaze B2, Wasabi …) via an optional `endpoint_url`. New tars are
  # downloaded once into a local staging dir to parse them locally;
  # backup.sh writes the same staging dir before uploading.
  module S3 # rubocop:disable Metrics/ModuleLength
    # Pinned to an exact version: amazon/aws-cli publishes no major/minor
    # tags (only full semver + `latest`), so this is the closest we get to
    # the third-party pinning rule of ADR-0006. The S3 adapter parses the
    # CLI's text output, so an unpinned tag risks silent breakage.
    IMAGE = 'amazon/aws-cli:2.34.52'.freeze
    STAGING_DIRNAME = 'backups-staging'.freeze

    class << self
      include BackupRepository::Tracking
      include BackupRepository::Sidecar

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

      def record_backup!(filename) # rubocop:disable Metrics/MethodLength
        raise BackupRepository::NotFound unless BackupRepository.valid_filename?(filename)
        return nil unless destination_configured?

        FileUtils.mkdir_p(directory)
        path = ::File.join(directory, filename)
        begin
          download_to_staging!([filename])
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

        stream_sidecar_download('aws', 's3', 'cp', s3_uri(filename), '-', &)
      end

      def read_archive_for(filename)
        return BackupRepository::EMPTY_ARCHIVE unless destination_configured?

        stream_sidecar_archive('aws', 's3', 'cp', s3_uri(filename), '-')
      end

      def remove_files!(filenames)
        return if filenames.empty?
        return unless destination_configured?

        sidecar_run!('sh', '-c', destroy_script(filenames))
      end

      def read_error_file(filename = BackupRepository::ERROR_FILENAME)
        return nil unless destination_configured?

        output, status = sidecar_capture('sh', '-c', error_file_script(filename))
        return nil unless status.success?

        output.strip.presence
      end

      def remove_error_file!(filename = BackupRepository::ERROR_FILENAME)
        return unless destination_configured?

        sidecar_run!('sh', '-c', "aws s3 rm #{shellescape(s3_uri(filename))} 2>/dev/null || true")
      end

      # Normalizes empty / leading- / trailing-slash prefixes to a single
      # `bucket/prefix/filename` layout.
      def s3_uri(filename = nil)
        parts = [bucket, prefix.presence, filename].compact
        "s3://#{parts.join('/')}"
      end

      # Trailing-slash variant for shell concatenation inside backup.sh.
      def s3_dir_uri
        parts = [bucket, prefix.presence].compact
        "s3://#{parts.join('/')}/"
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

      # `-e` args for the detached runners' outer docker:cli container.
      # Omits AWS_REGION — the runner scripts only forward
      # AWS_DEFAULT_REGION to the nested aws-cli sidecar.
      def runner_env_args
        backup = Configuration.current.backup
        args = [
          '-e', "AWS_ACCESS_KEY_ID=#{backup.aws_access_key_id}",
          '-e', "AWS_SECRET_ACCESS_KEY=#{backup.aws_secret_access_key}",
          '-e', "AWS_DEFAULT_REGION=#{backup.aws_region}"
        ]
        args.push('-e', "AWS_ENDPOINT_URL=#{endpoint_url}") if endpoint_url
        args
      end

      private

      def error_file_script(filename)
        <<~SH
          if aws s3 cp #{shellescape(s3_uri(filename))} - 2>/dev/null; then
            :
          fi
        SH
      end

      def destroy_script(filenames)
        commands = filenames.flat_map do |filename|
          legacy = "#{filename}#{BackupRepository::LEGACY_MANIFEST_SUFFIX}"
          [
            "aws s3 rm #{shellescape(s3_uri(filename))}",
            "aws s3 rm #{shellescape(s3_uri(legacy))} 2>/dev/null || true",
          ]
        end
        (['set -e'] + commands).join("\n")
      end

      def download_to_staging!(filenames)
        output, status = Open3.capture2e(*download_command(filenames))
        return if status.success?

        raise BackupRepository::Error, output.to_s.strip.presence || "exited #{status.exitstatus}"
      end

      # `docker run` argument array (never a shell string) for
      # `aws s3 cp --recursive` restricted to the wanted objects. Two
      # `--include` patterns per file so the filter matches whether
      # aws-cli applies it to the prefix-relative name or the full key.
      def download_command(filenames)
        includes = filenames.flat_map { |name| ['--include', name, '--include', "*/#{name}"] }
        [
          'docker', 'run', '--rm', *aws_env_args,
          '-v', "#{host_directory}:/output",
          '--entrypoint', 'aws', IMAGE,
          's3', 'cp', s3_dir_uri, '/output/', '--recursive', '--exclude', '*', *includes
        ]
      end

      # amazon/aws-cli's default entrypoint is `aws`, so an unspecified
      # entrypoint would forward every argument to the AWS CLI. Pull the
      # binary out of `cmd` and pass it via `--entrypoint` so this helper
      # covers both `aws s3 …` and the `sh -c '<script>'` form.
      def sidecar_command(*cmd)
        entrypoint, *args = cmd
        [
          'docker', 'run', '--rm',
          *aws_env_args,
          '--entrypoint', entrypoint,
          IMAGE,
          *args
        ]
      end

      # Adds AWS_REGION on top of #runner_env_args: aws-cli honours it
      # too, whereas the runner shell scripts only need AWS_DEFAULT_REGION.
      def aws_env_args
        runner_env_args + ['-e', "AWS_REGION=#{Configuration.current.backup.aws_region}"]
      end

      def shellescape(value)
        ::Shellwords.escape(value.to_s)
      end
    end
  end
end
