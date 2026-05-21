require 'shellwords'
require 'open3'

class BackupRepository
  # aws-cli-backed storage adapter for S3 and S3-compatible object stores
  # (MinIO, Backblaze B2, Wasabi …) via an optional `endpoint_url`.
  #
  # Every list / find / error read is served from the shared JSON index
  # (IndexedAdapter); detached-run detection and the sidecar helpers come
  # from SidecarAdapter. `refresh!` rebuilds the index in at most two
  # short-lived `amazon/aws-cli` sidecars regardless of the backup count —
  # one to list the bucket, one to bulk-download what needs (re)reading.
  #
  # The "host directory" returned to BackupRunner is a local staging dir
  # (`${data_path}/helios/backups-staging`): backup.sh writes the tar there
  # before uploading it to S3, and `refresh!` reuses the same dir to
  # bulk-download backup metadata. Both leave it empty again afterwards.
  module S3 # rubocop:disable Metrics/ModuleLength
    # Pinned to an exact version: amazon/aws-cli publishes no major/minor
    # tags (only full semver + `latest`), so this is the closest we get to
    # the third-party pinning rule of ADR-0006. The S3 adapter parses the
    # CLI's text output, so an unpinned tag risks silent breakage.
    IMAGE = 'amazon/aws-cli:2.34.52'.freeze
    STAGING_DIRNAME = 'backups-staging'.freeze

    class << self
      include BackupRepository::IndexedAdapter
      include BackupRepository::SidecarAdapter

      # Container-internal staging path: where the detached backup writer
      # lands the tar before backup.sh uploads it. Always returned (even
      # when the destination is not yet configured) so callers that mkdir
      # the directory up front don't have to branch on configuration state.
      def directory
        ::File.join(Rails.configuration.data_path, 'helios', STAGING_DIRNAME)
      end

      # Host-side staging directory used as the bind-mount source for
      # backup.sh's `/output`. Nil when the destination is not fully
      # configured so BackupRunner.unavailable_reason flags it the same
      # way an external mount without a configured path is flagged.
      def host_directory
        return nil unless destination_configured?

        ::File.join(Orchestration::Runner.host_data_path, 'helios', STAGING_DIRNAME)
      end

      # True once the survey carries every field the aws-cli sidecar needs.
      def destination_configured?
        backup = Configuration.current.backup
        backup.aws_bucket.present? &&
          backup.aws_access_key_id.present? &&
          backup.aws_secret_access_key.present? &&
          backup.aws_region.present?
      end

      def destroy!(filename)
        raise BackupRepository::NotFound unless BackupRepository.valid_filename?(filename)

        ensure_index_fresh!
        index = read_index
        raise BackupRepository::NotFound unless index['backups'].any? { |entry| entry['filename'] == filename }

        sidecar_run!('sh', '-c', destroy_script(filename))
        index['backups'] = index['backups'].reject { |entry| entry['filename'] == filename }
        write_index(index)
      end

      def clear_error!(filename = BackupRepository::ERROR_FILENAME)
        return unless destination_configured?

        sidecar_run!('sh', '-c', "aws s3 rm #{shellescape(s3_uri(filename))} 2>/dev/null || true")
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

        sidecar_run!('sh', '-c', prune_script(stale))
        index['backups'] = index['backups'].first(keep)
        write_index(index)
      end

      # Streams the tar to a block in 64 KB chunks. The BackupsController
      # wraps this in an Enumerator-backed response_body so multi-GB
      # downloads don't buffer the whole archive in memory — the aws-cli
      # sidecar streams the object straight from S3 into the HTTP response.
      def download(filename, &)
        raise BackupRepository::NotFound unless downloadable?(filename)

        stream_sidecar_download('aws', 's3', 'cp', s3_uri(filename), '-', &)
      end

      # Used by RestoreRunner for archive validation. Streams the tar
      # through aws-cli and parses it on the fly.
      def read_archive_for(filename)
        return BackupRepository::EMPTY_ARCHIVE unless destination_configured?

        stream_sidecar_archive('aws', 's3', 'cp', s3_uri(filename), '-')
      end

      # Rebuilds the on-disk index from S3 in at most two short-lived
      # sidecars: run 1 is one `list-objects-v2` for the object listing;
      # run 2, only when something needs (re)reading, is one
      # `aws s3 cp --recursive` that bulk-downloads the new backup tars plus
      # the error files into the staging dir for HELIOS to parse locally.
      # The sidecar count is independent of the backup count.
      #
      # Returns the parsed state on a rebuild, nil when the listing sidecar
      # bailed (docker down, revoked credentials, an S3 outage) — never on a
      # merely empty bucket — so a transient outage keeps the stale index
      # and detect_completion! skips reconciliation.
      def refresh!
        unless destination_configured?
          Index.delete!
          return nil
        end

        objects = list_objects
        objects && rebuild_index(objects)
      end

      def pending_marker_path
        ::File.join(Rails.configuration.data_path, 'helios', 's3_backup_pending.flag')
      end

      # Builds the `s3://<bucket>/<prefix>/<filename>` URI used in every
      # aws-cli call. Prefix is normalized — leading/trailing slashes are
      # stripped and a single `/` is inserted between segments so survey
      # values like "solectrus", "solectrus/" and "/solectrus/" produce
      # the same key layout.
      def s3_uri(filename = nil)
        parts = [bucket, prefix.presence, filename].compact
        "s3://#{parts.join('/')}"
      end

      # Prefix URI with a trailing slash, suitable for shell concatenation
      # inside backup.sh (`${S3_DIR_URI}${BACKUP_FILENAME}`). Empty prefix
      # collapses to `s3://<bucket>/`.
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

      # Strips leading/trailing slashes so survey values like "solectrus",
      # "solectrus/" and "/solectrus/" all map to the same S3 key layout.
      # Shared with Backup::ConnectionTest so the probe targets the exact
      # prefix the live adapter writes to.
      def normalize_prefix(value)
        value.to_s.strip.gsub(%r{\A/+|/+\z}, '')
      end

      def endpoint_url
        Configuration.current.backup.s3_endpoint_url.to_s.strip.presence
      end

      # AWS credential `-e` args for the detached backup/restore runners.
      # The outer docker:cli container carries them so backup.sh/restore.sh
      # can re-export them to the nested aws-cli sidecar. Omits AWS_REGION —
      # the runner scripts only forward AWS_DEFAULT_REGION downstream.
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

      def in_progress_cache_key
        'helios_s3_backup_in_progress'
      end

      def downloadable?(filename)
        return false unless BackupRepository.valid_filename?(filename)
        return false unless destination_configured?

        ensure_index_fresh!
        read_index['backups'].any? { |entry| entry['filename'] == filename }
      end

      def cache_fresh?
        index = Index.read
        return false unless index

        index['destination'] == 's3' &&
          index['bucket'] == bucket &&
          index['prefix'] == prefix &&
          index['endpoint_url'] == endpoint_url &&
          index_complete?(index)
      end

      def read_index
        Index.read || { 'backups' => [], 'bucket' => bucket, 'prefix' => prefix,
                        'endpoint_url' => endpoint_url, 'error_message' => nil, 'restore_error_message' => nil }
      end

      # Run 1: lists every object under the prefix in one sidecar, emitting
      # `OBJ|<key>|<size>|<mtime>` per line. The listing is captured before
      # the awk pipe so an aws-cli failure (revoked credentials, an S3-side
      # outage) propagates as a non-zero exit instead of being masked into an
      # empty result — `list-objects-v2` exits 0 for a genuinely empty
      # bucket, so the empty-but-reachable case still exits cleanly.
      def list_objects
        output, status = sidecar_capture('sh', '-c', list_script)
        return nil unless status.success?

        output.each_line.filter_map { |line| parse_object_line(line.chomp) }
      end

      def list_script
        list_prefix = prefix.empty? ? '' : "#{prefix}/"
        <<~SH
          if ! out="$(aws s3api list-objects-v2 --bucket #{shellescape(bucket)} --prefix #{shellescape(list_prefix)} \
            --query 'Contents[].[Key,Size,LastModified]' --output text 2>/dev/null)"; then
            exit 3
          fi
          printf '%s\\n' "$out" | awk 'NF >= 3 { printf "OBJ|%s|%s|%s\\n", $1, $2, $3 }'
        SH
      end

      def parse_object_line(line)
        marker, key, size, mtime = line.split('|', 4)
        return nil unless marker == 'OBJ' && key && size && mtime

        { key: key, size: size.to_i, mtime: parse_mtime(mtime) }
      rescue ArgumentError
        nil
      end

      def parse_mtime(value)
        Time.zone.parse(value) || Time.zone.at(value.to_i)
      end

      # Builds and writes the index from the run-1 listing. A backup tar
      # already in the cache is reused as-is: an S3 tar is immutable (unique
      # timestamped name, never overwritten — uploads only target the local
      # destination), so a cached entry stays valid as long as the object
      # exists. The rest, plus the error files, are bulk-downloaded by run 2.
      def rebuild_index(objects)
        tars = backup_objects(objects)
        previous = (Index.read || {}).fetch('backups', []).index_by { |entry| entry['filename'] }
        stale = tars.reject { |tar| reusable?(previous[tar[:filename]]) }
        archives, errors = fetch_from_staging!(stale.pluck(:filename), error_object_names(objects))

        write_rebuilt_index(tars, previous, archives, errors)
      end

      # Names of the error files (error.txt / restore-error.txt) present in
      # the listing — fetched alongside the stale tars by run 2.
      def error_object_names(objects)
        objects.map { |object| ::File.basename(object[:key]) }
               .select { |filename| error_files.key?(filename) }
      end

      def write_rebuilt_index(tars, previous, archives, errors) # rubocop:disable Metrics/MethodLength
        backups = tars.map do |tar|
          cached = previous[tar[:filename]]
          reusable?(cached) ? cached : entry_from_archive(tar, archives[tar[:filename]])
        end
        error_message = errors[BackupRepository::ERROR_FILENAME]
        restore_error_message = errors[RestoreRunner::ERROR_FILENAME]
        Index.write(
          'destination' => 's3',
          'bucket' => bucket,
          'prefix' => prefix,
          'endpoint_url' => endpoint_url,
          'updated_at' => Time.current.iso8601,
          'backups' => backups,
          'error_message' => error_message,
          'restore_error_message' => restore_error_message,
        )
        { listing: tars, error_message:, restore_error_message: }
      end

      # Backup tars from the raw object listing, newest first.
      def backup_objects(objects)
        objects
          .filter_map do |object|
            filename = ::File.basename(object[:key])
            next unless BackupRepository.valid_filename?(filename)

            { filename: filename, bytes: object[:size], mtime: object[:mtime] }
          end
          .sort_by { |tar| [tar[:mtime], tar[:filename]] }
          .reverse
      end

      # An S3 backup tar is immutable, so a cached index entry is reused as
      # long as the object exists; only an entry with empty `files` (a failed
      # earlier read) is rebuilt.
      def reusable?(cached)
        cached && Array(cached['files']).any?
      end

      # Run 2: one `aws s3 cp --recursive` pulls every wanted object into the
      # bind-mounted staging dir; HELIOS parses the tars locally (amazon/aws-cli
      # ships no `tar`) and reads the error files, then clears the staging dir.
      # A failed download yields empty results — the affected entries land in
      # the index with empty `files`, which cache_fresh? treats as stale so
      # the next visit retries — and the staging dir is cleared either way.
      def fetch_from_staging!(tar_filenames, error_filenames)
        wanted = tar_filenames + error_filenames
        return [{}, {}] if wanted.empty?

        FileUtils.mkdir_p(directory)
        download_to_staging!(wanted)
        [
          tar_filenames.index_with { |name| read_staged_archive(name) },
          error_filenames.index_with { |name| read_staged_text(name) },
        ]
      rescue BackupRepository::Error => e
        Rails.logger.warn("#{name}: bulk download failed — #{e.message}")
        [{}, {}]
      ensure
        wanted.each { |name| FileUtils.rm_f(::File.join(directory, name)) }
      end

      def download_to_staging!(filenames)
        output, status = Open3.capture2e(*download_command(filenames))
        return if status.success?

        raise BackupRepository::Error, output.to_s.strip.presence || "exited #{status.exitstatus}"
      end

      # `docker run` argument array (never a shell string) for the run-2
      # `aws s3 cp --recursive` restricted to the wanted objects. Two
      # `--include` patterns per file so the filter matches whether aws-cli
      # applies it to the prefix-relative name (`<file>`) or the full key
      # (`<prefix>/<file>`); neither pattern over-matches a sibling object.
      def download_command(filenames)
        includes = filenames.flat_map { |name| ['--include', name, '--include', "*/#{name}"] }
        [
          'docker', 'run', '--rm', *aws_env_args,
          '-v', "#{host_directory}:/output",
          '--entrypoint', 'aws', IMAGE,
          's3', 'cp', s3_dir_uri, '/output/', '--recursive', '--exclude', '*', *includes
        ]
      end

      def read_staged_archive(filename)
        BackupRepository.read_archive(::File.join(directory, filename))
      end

      def read_staged_text(filename)
        ::File.read(::File.join(directory, filename)).strip.presence
      rescue Errno::ENOENT
        nil
      end

      def entry_from_archive(meta, archive)
        archive ||= BackupRepository::EMPTY_ARCHIVE
        images = BackupRepository.images_from_config(archive.config)
        {
          'filename' => meta[:filename],
          'bytes' => meta[:bytes],
          'mtime' => meta[:mtime].iso8601,
          'files' => archive.entries.map { |entry| { 'name' => entry.name, 'bytes' => entry.bytes } },
          'influxdb_image' => images[:influxdb],
          'postgresql_image' => images[:postgresql],
        }
      end

      def destroy_script(filename)
        primary = s3_uri(filename)
        legacy = s3_uri("#{filename}#{BackupRepository::LEGACY_MANIFEST_SUFFIX}")
        <<~SH
          set -e
          aws s3 rm #{shellescape(primary)}
          aws s3 rm #{shellescape(legacy)} 2>/dev/null || true
        SH
      end

      def prune_script(stale)
        commands = stale.flat_map do |entry|
          legacy = "#{entry['filename']}#{BackupRepository::LEGACY_MANIFEST_SUFFIX}"
          [
            "aws s3 rm #{shellescape(s3_uri(entry['filename']))}",
            "aws s3 rm #{shellescape(s3_uri(legacy))} 2>/dev/null || true",
          ]
        end
        (['set -e'] + commands).join("\n")
      end

      # amazon/aws-cli's default entrypoint is `aws`, so a `docker run`
      # without an explicit entrypoint forwards every argument to the AWS
      # CLI. Pull the binary out of the command and pass it through
      # `--entrypoint` so the same helper covers both `aws s3 …` and the
      # `sh -c '<inline-script>'` form.
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

      # Adds AWS_REGION on top of #runner_env_args: aws-cli honours it too,
      # whereas the runner shell scripts only need AWS_DEFAULT_REGION.
      def aws_env_args
        runner_env_args + ['-e', "AWS_REGION=#{Configuration.current.backup.aws_region}"]
      end

      def shellescape(value)
        ::Shellwords.escape(value.to_s)
      end
    end
  end
end
