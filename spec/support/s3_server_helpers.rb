require 'open3'

# Helpers for integration specs that exercise the S3 backup adapter against
# a throwaway, real S3-compatible server (MinIO).
#
# MinIO is used as a deliberately **pinned** test fixture. MinIO stopped
# publishing pre-built container images to Docker Hub in October 2025, so
# `minio/minio:RELEASE.2025-09-07` is the last officially published image
# there — which suits a test fixture fine: a frozen, durably tag-pinnable
# image is exactly what reproducible CI wants. MinIO validates SigV4, so it
# returns the real `NoSuchBucket` / `SignatureDoesNotMatch` /
# `InvalidAccessKeyId` codes the adapter classifies — a pure mock that
# skips auth could not test that, and it is faster per request than the
# maintained S3-compatible alternatives (SeaweedFS, Garage).
#
# The server runs on the default bridge network. HELIOS reaches S3 only
# through aws-cli sidecars, which share that network, so the endpoint
# HELIOS is configured with is the server's bridge IP — no host port.
#
# The aws-cli sidecars here deliberately use `BackupRepository::S3::IMAGE`,
# the same pinned image HELIOS uses, so a version bump is exercised by both
# the arrange steps and the code under test.
module S3ServerHelpers
  S3_SERVER_IMAGE = 'minio/minio:RELEASE.2025-09-07T16-13-09Z'.freeze
  S3_ACCESS_KEY = 'helios-integration-test'.freeze
  S3_SECRET_KEY = 'helios-integration-test-secret'.freeze

  S3Server = Struct.new(:container, :endpoint, :access_key, :secret_key, keyword_init: true)

  attr_reader :s3_server

  def start_s3_server!
    name = "helios-itest-s3-#{ENV.fetch('TEST_ENV_NUMBER', '0')}"
    system('docker', 'rm', '-f', name, out: File::NULL, err: File::NULL)
    run_s3_container!(name)

    @s3_server = S3Server.new(
      container: name,
      endpoint: "http://#{container_bridge_ip(name)}:9000",
      access_key: S3_ACCESS_KEY,
      secret_key: S3_SECRET_KEY,
    )
    wait_for_s3_server!
    @s3_server
  rescue StandardError
    # Don't leak the container if bridge-IP lookup or the readiness poll fails.
    system('docker', 'rm', '-f', name, out: File::NULL, err: File::NULL)
    raise
  end

  def stop_s3_server!
    return unless @s3_server

    system('docker', 'rm', '-f', @s3_server.container, out: File::NULL, err: File::NULL)
    @s3_server = nil
  end

  # Creates a bucket via an aws-cli sidecar, bypassing HELIOS code so the
  # spec's arrange step stays independent of the code under test.
  def s3_create_bucket!(bucket)
    aws_sidecar!('s3', 'mb', "s3://#{bucket}")
  end

  # Uploads a byte string as an object — used to seed backup tars and error
  # files before exercising the adapter.
  def s3_put_object!(bucket:, key:, body:)
    Dir.mktmpdir do |dir|
      File.binwrite(File.join(dir, 'payload'), body)
      aws_sidecar!('s3', 'cp', '/work/payload', "s3://#{bucket}/#{key}", mount: dir)
    end
  end

  # Object keys currently in the bucket, read via `s3api --output json` — a
  # different aws-cli code path than HELIOS's `--output text` parsing, so it
  # is a genuine independent check.
  def s3_object_keys(bucket)
    output = aws_sidecar!('s3api', 'list-objects-v2', '--bucket', bucket, '--output', 'json')
    return [] if output.strip.empty?

    Array(JSON.parse(output)['Contents']).pluck('Key')
  end

  private

  def run_s3_container!(name)
    output, status = Open3.capture2e(
      'docker', 'run', '-d', '--rm', '--name', name,
      '-e', "MINIO_ROOT_USER=#{S3_ACCESS_KEY}",
      '-e', "MINIO_ROOT_PASSWORD=#{S3_SECRET_KEY}",
      S3_SERVER_IMAGE, 'server', '/data'
    )
    raise "Failed to start MinIO: #{output}" unless status.success?
  end

  def aws_sidecar(*, mount: nil)
    cmd = [
      'docker', 'run', '--rm',
      '-e', "AWS_ACCESS_KEY_ID=#{@s3_server.access_key}",
      '-e', "AWS_SECRET_ACCESS_KEY=#{@s3_server.secret_key}",
      '-e', 'AWS_DEFAULT_REGION=us-east-1',
      '-e', "AWS_ENDPOINT_URL=#{@s3_server.endpoint}"
    ]
    cmd.push('-v', "#{mount}:/work") if mount
    cmd.push(BackupRepository::S3::IMAGE, *)

    Open3.capture2e(*cmd)
  end

  def aws_sidecar!(*args, mount: nil)
    output, status = aws_sidecar(*args, mount:)
    raise "aws-cli sidecar failed (#{args.inspect}): #{output}" unless status.success?

    output
  end

  def container_bridge_ip(name)
    ip, status = Open3.capture2(
      'docker', 'inspect', '-f', '{{.NetworkSettings.Networks.bridge.IPAddress}}', name
    )
    raise "Could not read S3 server bridge IP for #{name}" unless status.success? && ip.strip.present?

    ip.strip
  end

  # Polls with a real `aws s3 ls` until it succeeds — confirms the S3 API is
  # actually serving, not just that the container started.
  def wait_for_s3_server!(timeout: 40)
    deadline = Time.current + timeout

    loop do
      _output, status = aws_sidecar('s3', 'ls')
      return if status.success?
      raise "MinIO did not become ready within #{timeout}s" if Time.current > deadline

      sleep 1
    end
  end
end

RSpec.configure { |config| config.include S3ServerHelpers }
