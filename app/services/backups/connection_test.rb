require 'open3'
require 'aws-sdk-s3'

module Backups
  # Probes the configured external backup path from inside a docker:cli
  # sidecar — the exact same mount the External storage adapter uses
  # at runtime, so a successful probe guarantees that listing and writing
  # will work too. Uses `--mount type=bind` (not `-v`) on purpose: that
  # form fails if the host source does not exist, instead of silently
  # creating an empty directory.
  #
  # The `aws_credentials` check follows the same pattern for the S3
  # destination, but reaches the bucket directly from the HELIOS process
  # via `aws-sdk-s3` (the same gem the S3 storage adapter uses), and
  # classifies the SDK's typed errors into specific i18n reasons.
  class ConnectionTest
    include ConnectionTesting::ResultBuilder

    PROBE_IMAGE = BackupRunner::IMAGE
    WRITE_PROBE_NAME = '.helios-write-test'.freeze

    SAFE_PATH = %r{\A/[A-Za-z0-9_/.-]+\z}

    EXIT_NOT_DIRECTORY = 10
    EXIT_NOT_WRITABLE = 11

    S3Probe = Data.define(:access, :secret, :region, :bucket, :prefix, :endpoint)

    def call(check:, values:)
      case check
      when 'external_path' then external_path(values)
      when 'aws_credentials' then aws_credentials(values)
      else result(false, :error)
      end
    end

    private

    def external_path(values)
      path = values['external_path'].to_s.strip
      return result(false, :incomplete) if path.blank?
      return result(false, :backup_path_not_absolute) unless path.start_with?('/')
      return result(false, :backup_path_invalid_chars) unless path.match?(SAFE_PATH)

      probe(path)
    rescue StandardError => e
      Rails.logger.warn("External backup path probe failed (#{e.class}): #{e.message}")
      result(false, :backup_path_error)
    end

    def probe(path)
      output, status = Open3.capture2e(*probe_command(path))
      classify(status, output)
    end

    def probe_command(path)
      [
        'docker', 'run', '--rm',
        '--mount', "type=bind,source=#{path},target=/probe",
        PROBE_IMAGE,
        'sh', '-c',
        "test -d /probe || exit #{EXIT_NOT_DIRECTORY}; " \
        "touch /probe/#{WRITE_PROBE_NAME} 2>/dev/null || exit #{EXIT_NOT_WRITABLE}; " \
        "rm -f /probe/#{WRITE_PROBE_NAME}"
      ]
    end

    def classify(status, output)
      case status.exitstatus
      when 0 then result(true, :backup_path_writable)
      when EXIT_NOT_DIRECTORY then result(false, :backup_path_not_directory)
      when EXIT_NOT_WRITABLE then result(false, :backup_path_not_writable)
      else missing_or_error(output)
      end
    end

    # Docker rejects a `--mount type=bind` with a missing source by exiting
    # before the inner `sh -c` runs — the failure shows up as a non-zero
    # status and a "no such file" message on stderr.
    def missing_or_error(output)
      if output.include?('no such file') || output.include?('does not exist')
        result(false, :backup_path_missing)
      else
        Rails.logger.warn("External backup path probe failed: #{output.strip}")
        result(false, :backup_path_error)
      end
    end

    def aws_credentials(values)
      probe = build_s3_probe(values)
      return result(false, :incomplete) if probe.nil?

      probe_s3(probe)
    rescue StandardError => e
      Rails.logger.warn("S3 credentials probe failed (#{e.class}): #{e.message}")
      result(false, :s3_error)
    end

    def build_s3_probe(values)
      fields = %w[aws_access_key_id aws_secret_access_key aws_region aws_bucket]
               .index_with { |key| values[key].to_s.strip }
      return nil if fields.value?('')

      S3Probe.new(
        access: fields['aws_access_key_id'], secret: fields['aws_secret_access_key'],
        region: fields['aws_region'], bucket: fields['aws_bucket'],
        prefix: BackupRepository::S3.normalize_prefix(values['s3_prefix']),
        endpoint: values['s3_endpoint_url'].to_s.strip
      )
    end

    # `list_objects_v2`, not `head_bucket`, is used on purpose: it returns
    # success regardless of whether the prefix has any objects (the normal
    # state of a freshly configured bucket) and additionally verifies that
    # list permissions are in place — exactly what later runtime use needs.
    def probe_s3(probe)
      client_for(probe).list_objects_v2(
        bucket: probe.bucket,
        prefix: probe.prefix.present? ? "#{probe.prefix}/" : nil,
        max_keys: 1,
      )
      result(true, :s3_reachable)
    rescue Aws::S3::Errors::ServiceError, Seahorse::Client::NetworkingError, Errno::ECONNREFUSED => e
      classify_s3_error(e)
    end

    def classify_s3_error(error)
      case error
      when Aws::S3::Errors::NoSuchBucket
        result(false, :s3_bucket_missing)
      when Aws::S3::Errors::InvalidAccessKeyId, Aws::S3::Errors::SignatureDoesNotMatch
        result(false, :s3_invalid_credentials)
      when Aws::S3::Errors::AccessDenied, Aws::S3::Errors::Forbidden
        result(false, :s3_access_denied)
      when Seahorse::Client::NetworkingError, Errno::ECONNREFUSED
        Rails.logger.warn("S3 credentials probe failed (network): #{error.class}: #{error.message}")
        result(false, :s3_endpoint_unreachable)
      else
        Rails.logger.warn("S3 credentials probe failed: #{error.class}: #{error.message}")
        result(false, :s3_error)
      end
    end

    def client_for(probe)
      BackupRepository::S3::ClientFactory.build(
        access_key_id: probe.access, secret_access_key: probe.secret,
        region: probe.region, endpoint: probe.endpoint
      )
    end
  end
end
