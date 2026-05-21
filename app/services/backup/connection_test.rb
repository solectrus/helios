require 'open3'

module Backup
  # Probes the configured external backup path from inside a docker:cli
  # sidecar — the exact same mount the External storage adapter uses
  # at runtime, so a successful probe guarantees that listing and writing
  # will work too. Uses `--mount type=bind` (not `-v`) on purpose: that
  # form fails if the host source does not exist, instead of silently
  # creating an empty directory.
  #
  # The `aws_credentials` check follows the same pattern for the S3
  # destination: an `amazon/aws-cli` sidecar runs `aws s3 ls` against the
  # configured bucket and prefix, then classifies AWS's error responses
  # into specific i18n reasons.
  class ConnectionTest
    include ConnectionTesting::ResultBuilder

    PROBE_IMAGE = 'docker:cli'.freeze
    AWS_CLI_IMAGE = 'amazon/aws-cli:latest'.freeze
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
        prefix: values['s3_prefix'].to_s.strip.gsub(%r{\A/+|/+\z}, ''),
        endpoint: values['s3_endpoint_url'].to_s.strip
      )
    end

    def probe_s3(probe)
      output, status = Open3.capture2e(*aws_probe_command(probe))
      classify_s3(status, output)
    end

    def aws_probe_command(probe)
      env_args = [
        '-e', "AWS_ACCESS_KEY_ID=#{probe.access}",
        '-e', "AWS_SECRET_ACCESS_KEY=#{probe.secret}",
        '-e', "AWS_DEFAULT_REGION=#{probe.region}"
      ]
      env_args.push('-e', "AWS_ENDPOINT_URL=#{probe.endpoint}") unless probe.endpoint.empty?

      ['docker', 'run', '--rm', *env_args, AWS_CLI_IMAGE, 's3', 'ls', probe_uri(probe)]
    end

    def probe_uri(probe)
      parts = [probe.bucket, probe.prefix.presence].compact
      "s3://#{parts.join('/')}/"
    end

    def classify_s3(status, output)
      return result(true, :s3_reachable) if status.success?

      case output
      when /NoSuchBucket/i then result(false, :s3_bucket_missing)
      when /InvalidAccessKeyId|SignatureDoesNotMatch/i then result(false, :s3_invalid_credentials)
      when /AccessDenied|Forbidden/i then result(false, :s3_access_denied)
      when /Could not connect|Failed to connect|name or service not known|NameResolutionError|EndpointConnectionError/i
        result(false, :s3_endpoint_unreachable)
      else
        Rails.logger.warn("S3 credentials probe failed: #{output.strip}")
        result(false, :s3_error)
      end
    end
  end
end
