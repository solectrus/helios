# End-to-end coverage of the restore path: a real BackupRunner produces a
# tar from a live PostgreSQL + InfluxDB stack, then RestoreRunner tears
# the stack down, wipes the data directories and rebuilds it from the
# tar. Because the rebuild starts Postgres on an empty data dir, the
# image runs initdb plus its bootstrap server — the exact scenario the
# TCP probe in restore.sh guards against. Without that probe the first
# psql call would race the bootstrap and die with "Connection refused".
#
# Tagged :integration by its spec/integration/ location. Slow: pulls
# Postgres, InfluxDB and docker:cli images, runs a real backup and a
# real restore (which itself starts the stack twice).
RSpec.describe RestoreRunner, :docker_stack do
  let(:data_path) { Rails.root.join("tmp/restore-itest#{ENV.fetch('TEST_ENV_NUMBER', nil)}").to_s }

  before do
    skip_without_docker

    allow(Rails.configuration).to receive(:data_path).and_return(data_path)
    FileUtils.mkdir_p(data_path)
    write_config!
    Export::Builder.new(Configuration.current).write!
    compose_down!(data_path) # clear leftovers from a previous interrupted run
  end

  after do
    compose_down!(data_path)
    clear_data_path!(data_path, cleanup_image: described_class::IMAGE)
  end

  describe '.start (real restore against a freshly initialized data directory)' do
    it 'rebuilds the stack from the backup tar and restores the seeded marker row' do
      Orchestration::Runner.start('postgresql', 'influxdb')
      wait_for_postgresql_ready!
      wait_for_healthy!('influxdb')
      create_production_database!
      seed_marker_row!

      filename = produce_backup_tar!
      expect(filename).not_to be_nil, 'no backup tar was produced'

      described_class.start(filename)
      wait_for_container_exit!(described_class::CONTAINER_NAME, timeout: 360)

      aggregate_failures do
        expect(restore_error_message).to be_nil,
                                         "restore failed: #{restore_error_message}"
        # Restore re-initialises postgres on an empty data dir — verify the
        # production database came back with its seeded row, proving the
        # restore script got past the bootstrap-server race.
        wait_for_postgresql_ready!
        expect(marker_rows).to eq(['restored'])
      end
    end
  end

  # --- helpers ---

  # Minimal HELIOS configuration with a local backup destination —
  # Export::Builder.ensure_defaults! materializes postgresql, influxdb,
  # redis, dashboard (passwords, tokens, images). No publish_port, so
  # the stack does not clash with other dev containers.
  def write_config!
    data = { 'backup' => { 'destination' => 'local' } }
    FileUtils.mkdir_p(File.dirname(Configuration.path))
    File.write(Configuration.path, YAML.dump(data))
    Current.reset
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

  # Marker the restore must bring back — distinct enough that an empty
  # restored cluster would obviously fail the assertion.
  def seed_marker_row!
    psql_in_production!('CREATE TABLE restore_marker (name text)')
    psql_in_production!("INSERT INTO restore_marker (name) VALUES ('restored')")
  end

  def marker_rows
    stdout, stderr, code = Orchestration::Runner.compose_exec(
      'postgresql', 'psql', '-U', 'postgres', '-d', 'solectrus_production',
      '-tAc', 'SELECT name FROM restore_marker ORDER BY name'
    )
    raise "marker query failed: #{stderr}" unless code&.zero?

    stdout.split("\n").map(&:strip).reject(&:empty?)
  end

  def psql_in_production!(sql)
    _stdout, stderr, code = Orchestration::Runner.compose_exec(
      'postgresql', 'psql', '-U', 'postgres', '-d', 'solectrus_production', '-c', sql
    )
    raise "SQL failed (#{sql}): #{stderr}" unless code&.zero?
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
  # server, so a query racing it dies with "Connection refused". A TCP probe
  # stays negative until the real server is up.
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

  # Runs a real backup to completion (handling the async pull + launch) and
  # returns the produced tar filename, so the restore has something to chew on.
  def produce_backup_tar!
    BackupRunner.start
    wait_for_backup_launch!
    wait_for_container_exit!(BackupRunner::CONTAINER_NAME)
    BackupRepository.detect_completion!
    expect(BackupRepository.error_message).to be_nil, "backup failed: #{BackupRepository.error_message}"
    produced_backup_filename
  end

  # BackupRunner pulls the image + launches its container on a background
  # thread; wait for that thread to finish so the container exists before we
  # poll for its exit.
  def wait_for_backup_launch!(timeout: 240)
    deadline = Time.current + timeout
    until Time.current > deadline
      return true unless BackupRunner.preparing?

      sleep 0.5
    end
    raise "backup preparing thread did not finish within #{timeout}s"
  end

  # The detached runner uses `--rm`, so its disappearance from `docker ps`
  # marks the script done.
  def wait_for_container_exit!(name, timeout: 240)
    deadline = Time.current + timeout
    until Time.current > deadline
      running, = Open3.capture2('docker', 'ps', '-aq', '--filter', "name=#{name}")
      return true if running.strip.empty?

      sleep 0.5
    end
    raise "#{name} did not exit within #{timeout}s"
  end

  def produced_backup_filename
    File.basename(Dir.glob(File.join(data_path, 'helios', 'backups', 'solectrus-backup-*.tar')).first.to_s).presence
  end

  def restore_error_message
    File.read(File.join(data_path, 'helios', 'backups', RestoreRunner::ERROR_FILENAME)).strip.presence
  rescue Errno::ENOENT
    nil
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
end
