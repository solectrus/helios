require 'securerandom'

# End-to-end coverage of the S3 backup path: a real detached BackupRunner
# `docker:cli` container dumps a live PostgreSQL + InfluxDB stack, bundles
# the tar and uploads it to a real S3 bucket (MinIO) through the
# nested, pinned `amazon/aws-cli` sidecar that backup.sh spawns.
#
# This is the only test that exercises the full chain at once — the outer
# docker:cli container, the AWS-credential env forwarding into the nested
# aws-cli container, and the staging-dir mechanics — so it guards both
# pinned images (docker:cli and amazon/aws-cli) together.
#
# Restore-from-S3 is intentionally not covered here: a restore tears the
# whole stack down, wipes the data directories and rebuilds it, which is
# far heavier and destructive. The S3 download path it relies on is
# already covered by spec/integration/backup_repository/s3_spec.rb.
#
# Tagged :integration by its spec/integration/ location. Slow: pulls
# Postgres, InfluxDB, docker:cli and aws-cli images and runs a real backup.
RSpec.describe BackupRunner, :docker_stack do
  let(:data_path) { Rails.root.join("tmp/backup-s3-itest#{ENV.fetch('TEST_ENV_NUMBER', nil)}").to_s }
  let(:bucket) { "helios-itest-#{SecureRandom.hex(6)}" }
  let(:prefix) { 'solectrus' }

  before(:all) { start_s3_server! if docker_available? }

  after(:all) { stop_s3_server! }

  before do
    skip_without_docker

    allow(Rails.configuration).to receive(:data_path).and_return(data_path)
    FileUtils.mkdir_p(data_path)
    write_config!
    Export::Builder.new(Configuration.current).write!
    s3_create_bucket!(bucket)
    compose_down!(data_path) # clear leftovers from a previous interrupted run
  end

  after do
    compose_down!(data_path)
    remove_data_path!(data_path, cleanup_image: described_class::IMAGE)
  end

  describe '.start (real backup uploaded to S3)' do
    it 'dumps the live stack and uploads the tar to the S3 bucket' do
      Orchestration::Runner.start('postgresql', 'influxdb')
      wait_for_postgresql_ready!
      wait_for_healthy!('influxdb')
      create_production_database!

      described_class.start
      wait_for_backup_completion!

      expect(BackupRepository::S3.error_message).to be_nil,
                                                    "backup failed: #{BackupRepository::S3.error_message}"

      backups = BackupRepository::S3.all
      aggregate_failures do
        expect(backups.size).to eq(1)
        expect(s3_object_keys(bucket)).to contain_exactly("#{prefix}/#{backups.first.filename}")
        expect(backups.first.files.map(&:name)).to include(
          'helios/config.yaml',
          a_string_matching(/solectrus-postgresql-backup/),
          a_string_matching(/solectrus-influxdb-backup/),
        )
        # The S3 destination keeps no local archive — the staging dir holds
        # the tar only while the upload is in flight.
        expect(Dir.children(File.join(data_path, 'helios', 'backups-staging'))).to be_empty
      end
    end
  end

  # --- helpers ---

  # Minimal HELIOS configuration with only the backup section seeded —
  # Export::Builder.ensure_defaults! materializes the rest (passwords, tokens,
  # images) for postgresql, influxdb, redis and dashboard. No `publish_port`
  # is set, so no service publishes a host port and the stack coexists with
  # other dev containers on 8086. The backup script reaches both databases
  # via `docker exec` over the compose network, so host ports are not needed.
  def write_config!
    data = { 'backup' => backup_config }
    FileUtils.mkdir_p(File.dirname(Configuration.path))
    File.write(Configuration.path, YAML.dump(data))
    Current.reset
  end

  def backup_config
    {
      'destination' => 's3',
      'aws_bucket' => bucket,
      'aws_access_key_id' => s3_server.access_key,
      'aws_secret_access_key' => s3_server.secret_key,
      'aws_region' => 'us-east-1',
      's3_prefix' => prefix,
      's3_endpoint_url' => s3_server.endpoint,
    }
  end

  # backup.sh dumps `solectrus_production` — the database the SOLECTRUS
  # dashboard creates at runtime. The dashboard is not part of this test,
  # so the database is created explicitly.
  def create_production_database!
    _stdout, stderr, code = Orchestration::Runner.compose_exec(
      'postgresql', 'psql', '-U', 'postgres', '-c', 'CREATE DATABASE solectrus_production'
    )
    raise "creating solectrus_production failed: #{stderr}" unless code&.zero?
  end

  def wait_for_healthy!(service, timeout: 180)
    deadline = Time.current + timeout

    loop do
      Orchestration::Container.invalidate_cache
      container = Orchestration::Container.find(service)
      return container if container&.healthy?
      if Time.current > deadline
        raise "#{service} did not become healthy within #{timeout}s\n#{healthy_diagnostics(service)}"
      end

      sleep 2
    end
  end

  # On a first-time start the postgres image runs a temporary bootstrap server
  # that listens on the Unix socket only. The container healthcheck
  # (`pg_isready` over that socket) can flip to "healthy" against the throwaway
  # server, which then shuts down — so a query racing it dies with "the
  # database system is shutting down". A TCP probe stays negative until the
  # real server is up.
  def wait_for_postgresql_ready!(timeout: 180)
    wait_for_healthy!('postgresql', timeout:)
    deadline = Time.current + timeout

    until postgresql_accepting_tcp_connections?
      raise "postgresql did not accept TCP connections within #{timeout}s" if Time.current > deadline

      sleep 1
    end
  end

  def postgresql_accepting_tcp_connections?
    _stdout, _stderr, code = Orchestration::Runner.compose_exec(
      'postgresql', 'pg_isready', '-h', '127.0.0.1', '-U', 'postgres', '-q'
    )
    code&.zero?
  end

  # Container state plus its last log lines — surfaced in the failure
  # message so a CI timeout is debuggable without a re-run.
  def healthy_diagnostics(service)
    container = Orchestration::Container.find(service)
    state =
      if container
        "status=#{container.status} health=#{container.health_status.inspect}"
      else
        'container not found'
      end
    ps, = Open3.capture2e('docker', 'ps', '-a')
    logs, = container ? Open3.capture2e('docker', 'logs', '--tail', '40', container.name) : ['', nil]
    "[#{service}] #{state}\n--- docker ps -a ---\n#{ps}\n--- #{service} logs ---\n#{logs}"
  end

  # The backup runs in a detached `--rm` container, so its disappearance
  # from `docker ps` marks completion (success or failure alike).
  def wait_for_backup_completion!(timeout: 240)
    deadline = Time.current + timeout

    loop do
      running, = Open3.capture2('docker', 'ps', '-aq', '--filter', "name=#{described_class::CONTAINER_NAME}")
      return if running.strip.empty?
      raise "backup runner did not finish within #{timeout}s" if Time.current > deadline

      sleep 2
    end
  end
end
