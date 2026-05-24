require 'open3'
require 'aws-sdk-s3'

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
# MinIO publishes its API on a 127.0.0.1 host port (one per turbo_tests
# worker via TEST_ENV_NUMBER). aws-sdk-s3 in the test process — and the
# adapter under test in the runtime — both reach MinIO through the host
# port, which keeps WebMock's `allow_localhost: true` default in play.
#
# The arrange steps here use a separate aws-sdk-s3 Client so a bug in
# the adapter's own client cannot silently fix or mask itself by sharing
# the seeding code path.
module S3ServerHelpers
  S3_SERVER_IMAGE = 'minio/minio:RELEASE.2025-09-07T16-13-09Z'.freeze
  S3_ACCESS_KEY = 'helios-integration-test'.freeze
  S3_SECRET_KEY = 'helios-integration-test-secret'.freeze

  # Each worker (turbo_tests) needs its own port so parallel runs don't
  # collide on the same MinIO listener.
  S3_HOST_PORT_BASE = 19_000

  S3Server = Struct.new(:container, :endpoint, :access_key, :secret_key, keyword_init: true)

  attr_reader :s3_server

  def start_s3_server!
    name = "helios-itest-s3-#{ENV.fetch('TEST_ENV_NUMBER', '0')}"
    port = s3_host_port
    system('docker', 'rm', '-f', name, out: File::NULL, err: File::NULL)
    run_s3_container!(name, port)

    @s3_server = S3Server.new(
      container: name,
      endpoint: "http://127.0.0.1:#{port}",
      access_key: S3_ACCESS_KEY,
      secret_key: S3_SECRET_KEY,
    )
    wait_for_s3_server!
    @s3_server
  rescue StandardError
    # Don't leak the container if the readiness poll fails.
    system('docker', 'rm', '-f', name, out: File::NULL, err: File::NULL)
    raise
  end

  def stop_s3_server!
    return unless @s3_server

    system('docker', 'rm', '-f', @s3_server.container, out: File::NULL, err: File::NULL)
    @s3_server = nil
  end

  # Creates a bucket against the live MinIO via the seed client.
  def s3_create_bucket!(bucket)
    seed_client.create_bucket(bucket: bucket)
  end

  # Uploads a byte string as an object — used to seed backup tars and error
  # files before exercising the adapter.
  def s3_put_object!(bucket:, key:, body:)
    seed_client.put_object(bucket: bucket, key: key, body: body)
  end

  # Object keys currently in the bucket.
  def s3_object_keys(bucket)
    resp = seed_client.list_objects_v2(bucket: bucket)
    Array(resp.contents).map(&:key)
  end

  private

  def run_s3_container!(name, host_port)
    output, status = Open3.capture2e(
      'docker', 'run', '-d', '--rm', '--name', name,
      '-p', "127.0.0.1:#{host_port}:9000",
      '-e', "MINIO_ROOT_USER=#{S3_ACCESS_KEY}",
      '-e', "MINIO_ROOT_PASSWORD=#{S3_SECRET_KEY}",
      S3_SERVER_IMAGE, 'server', '/data'
    )
    raise "Failed to start MinIO: #{output}" unless status.success?
  end

  def s3_host_port
    S3_HOST_PORT_BASE + ENV.fetch('TEST_ENV_NUMBER', '0').to_i
  end

  # Independent aws-sdk-s3 client used by the spec's arrange steps. Built
  # once per running fixture so the live MinIO endpoint is the single
  # source of truth for both seed and probe paths.
  def seed_client
    @seed_client ||= Aws::S3::Client.new(
      region: 'us-east-1',
      credentials: Aws::Credentials.new(@s3_server.access_key, @s3_server.secret_key),
      endpoint: @s3_server.endpoint,
      force_path_style: true,
    )
  end

  # Polls with `list_buckets` until it succeeds — confirms the S3 API is
  # actually serving, not just that the container started.
  def wait_for_s3_server!(timeout: 40)
    deadline = Time.current + timeout

    loop do
      seed_client.list_buckets
      return
    rescue Seahorse::Client::NetworkingError, Aws::S3::Errors::ServiceError
      raise "MinIO did not become ready within #{timeout}s" if Time.current > deadline

      sleep 1
    end
  end
end

RSpec.configure { |config| config.include S3ServerHelpers }
