RSpec.describe BackupRunner do
  let(:data_path) { Dir.mktmpdir }
  let(:host_data_path) { '/host/data' }
  let(:state) do
    {
      open3_calls: [],
      docker_run_output: 'container-id',
      docker_run_success: true,
      docker_pull_output: '',
      docker_pull_success: true,
      docker_inspect_success: true,
      docker_inspect_running: true,
      docker_inspect_started_at: '2026-05-08T14:30:00Z',
      docker_inspect_args: ['-c', 'script'],
    }
  end

  before do
    allow(Rails.configuration).to receive(:data_path).and_return(data_path)
    FileUtils.mkdir_p(File.join(data_path, 'helios'))
    File.write(File.join(data_path, '.env'), "INFLUX_ADMIN_TOKEN=secret-token\n")
    File.write(File.join(data_path, 'helios', 'config.yaml'), "system:\n  timezone: Europe/Berlin\n")

    allow(Orchestration::Runner).to receive(:host_data_path).and_return(host_data_path)
    allow(Orchestration::Container).to receive(:find).with('postgresql').and_return(
      instance_double(Orchestration::Container, name: 'solectrus-postgresql-1'),
    )
    allow(Orchestration::Container).to receive(:find).with('influxdb').and_return(
      instance_double(Orchestration::Container, name: 'solectrus-influxdb-1'),
    )
    allow(RestoreRunner).to receive(:running?).and_return(false)
    allow(CsvImportRunner).to receive_messages(running?: false, in_progress?: false)

    # Freeze the instant to 14:30 in the configured system timezone
    # (Europe/Berlin, set in the config.yaml above). The filename/date are
    # anchored to system_zone (via Time.now), so this stays deterministic even
    # though the spec's Time.zone is UTC — which also guards the bug: a UTC-zone
    # caller (the scheduler thread) must still produce a Berlin-local filename.
    frozen = ActiveSupport::TimeZone['Europe/Berlin'].local(2026, 5, 8, 14, 30, 0)
    allow(Time).to receive_messages(current: frozen, now: frozen.to_time)

    allow(Open3).to receive(:capture2e) do |*args|
      state[:open3_calls] << args
      stub_open3_response(args)
    end
    allow(Open3).to receive(:capture2) do |*args|
      state[:open3_calls] << args
      stub_open3_response(args)
    end
  end

  after { FileUtils.remove_entry(data_path) }

  describe '.start' do
    it 'launches docker:cli with the backup script and required mounts' do
      described_class.start

      run = find_backup_runner_call
      aggregate_failures do
        expect(run).to include('--name', 'helios-backup-runner')
        expect(run).to include('-v', '/var/run/docker.sock:/var/run/docker.sock')
        expect(run).to include('--mount', "type=bind,source=#{host_data_path}/helios/backups,target=/output")
        expect(run).to include('-v', "#{host_data_path}/helios/runners:/runtime")
        expect(run).to include('-v', "#{host_data_path}/influx-backup-staging:/influx-backup-staging")
        expect(run).to include('-v', "#{host_data_path}/helios/config.yaml:/config.yaml:ro")
        expect(run).to include('--entrypoint', 'sh', described_class::IMAGE, '-c')
      end
    end

    it 'passes runtime values as positional shell args (not interpolated)' do
      described_class.start

      run = find_backup_runner_call
      placeholder_index = run.index('_')
      expect(run[placeholder_index + 1, 5]).to eq(
        ['secret-token', 'solectrus-backup-20260508-143000.tar', '2026-05-08',
         'solectrus-postgresql-1', 'solectrus-influxdb-1'],
      )
    end

    it 'anchors the filename to the system timezone, not the caller thread (scheduler runs in UTC)' do
      # The scheduler thread has no per-request Time.zone, so it defaults to UTC.
      # The filename must still encode 14:30 Berlin (16:30 would be the UTC slip).
      Time.use_zone('UTC') { described_class.start }

      run = find_backup_runner_call
      placeholder_index = run.index('_')
      expect(run[placeholder_index + 2]).to eq('solectrus-backup-20260508-143000.tar')
    end

    it 'pulls docker:cli before launching so a stale local image is refreshed' do
      described_class.start

      expect(state[:open3_calls]).to include(['docker', 'pull', described_class::IMAGE])
    end

    it 'does not prune before launching — prune runs after a successful add' do
      allow(BackupRepository).to receive(:prune!)

      described_class.start

      expect(BackupRepository).not_to have_received(:prune!)
    end

    it 'clears a previous error file before launching' do
      FileUtils.mkdir_p(File.join(data_path, 'helios', 'runners'))
      File.write(File.join(data_path, 'helios', 'runners', 'error.txt'), 'old failure')

      described_class.start

      expect(File).not_to exist(File.join(data_path, 'helios', 'runners', 'error.txt'))
    end

    it 'creates the backups directory if missing' do
      described_class.start

      expect(File).to be_directory(File.join(data_path, 'helios', 'backups'))
    end

    it 'raises when helios/config.yaml is missing' do
      FileUtils.rm_f(File.join(data_path, 'helios', 'config.yaml'))

      expect { described_class.start }.to raise_error(described_class::Error, /config\.yaml is missing/)
    end

    it 'raises when .env is missing' do
      FileUtils.rm_f(File.join(data_path, '.env'))

      expect { described_class.start }.to raise_error(described_class::Error, /\.env file is missing/)
    end

    it 'raises when INFLUX_ADMIN_TOKEN is absent from .env' do
      File.write(File.join(data_path, '.env'), "OTHER=value\n")

      expect { described_class.start }.to raise_error(described_class::Error, /INFLUX_ADMIN_TOKEN/)
    end

    it 'raises when the PostgreSQL container is not running' do
      allow(Orchestration::Container).to receive(:find).with('postgresql').and_return(nil)

      expect { described_class.start }.to raise_error(described_class::Error, /PostgreSQL/)
    end

    it 'raises when the InfluxDB container is not running' do
      allow(Orchestration::Container).to receive(:find).with('influxdb').and_return(nil)

      expect { described_class.start }.to raise_error(described_class::Error, /InfluxDB/)
    end

    it 'raises when a restore is already running' do
      allow(RestoreRunner).to receive(:running?).and_return(true)

      expect { described_class.start }.to raise_error(described_class::Error, /restore is already/)
    end

    it 'translates a docker name conflict into a friendly error' do
      state[:docker_run_output] = 'docker: container name "/helios-backup-runner" is already in use'
      state[:docker_run_success] = false

      expect { described_class.start }.to raise_error(described_class::Error, /already in progress/)
    end

    it 'surfaces other docker run failures verbatim' do
      state[:docker_run_output] = 'Cannot connect to the Docker daemon'
      state[:docker_run_success] = false

      expect { described_class.start }.to raise_error(described_class::Error, /Cannot connect to the Docker daemon/)
    end

    it 'fails fast when the docker:cli pull fails' do
      state[:docker_pull_output] = 'network unreachable'
      state[:docker_pull_success] = false

      expect { described_class.start }.to raise_error(described_class::Error, /network unreachable/)
    end

    it 'marks every backup phase via set_phase so the UI can show progress' do
      described_class.start

      run = find_backup_runner_call
      script = run[run.index('-c') + 1]
      aggregate_failures do
        described_class::KNOWN_PHASES.each do |phase|
          expect(script).to include("set_phase #{phase}"),
                            "expected backup.sh to mark phase #{phase}"
        end
        expect(script).to include('rm -f "$PHASE_PATH"')
      end
    end

    context 'with external destination' do
      let(:external_path) { '/mnt/nas' }
      let(:probe_result) { ConnectionTesting::Result.new(ok: true, reason: :backup_path_writable) }

      before do
        with_config_yaml('backup' => { 'destination' => 'external', 'external_path' => external_path })
        File.write(File.join(Rails.configuration.data_path, '.env'), "INFLUX_ADMIN_TOKEN=secret-token\n")
        FileUtils.mkdir_p(File.join(Rails.configuration.data_path, 'helios'))
        allow_any_instance_of(Backups::ConnectionTest).to receive(:call).and_return(probe_result) # rubocop:disable RSpec/AnyInstance
      end

      it 'mounts the configured external path as /output via --mount type=bind' do
        described_class.start

        expect(find_backup_runner_call).to include(
          '--mount', "type=bind,source=#{external_path},target=/output"
        )
      end

      it 'aborts with destination_unreachable and never launches the runner when the probe fails' do
        allow_any_instance_of(Backups::ConnectionTest).to receive(:call).and_return( # rubocop:disable RSpec/AnyInstance
          ConnectionTesting::Result.new(ok: false, reason: :backup_path_missing),
        )
        expected = I18n.t(
          'backups.runner.errors.destination_unreachable',
          reason: I18n.t('configurations.connection_test.backup_path_missing'),
        )

        expect { described_class.start }.to raise_error(described_class::Error, expected)
        expect(find_backup_runner_call).to be_nil
      end
    end

    context 'with S3 destination' do
      let(:s3_client) { Aws::S3::Client.new(stub_responses: true, region: 'eu-central-1') }

      before do
        with_config_yaml(
          # Match the outer system timezone so the filename (anchored to
          # system_zone) stays 14:30 Berlin here too.
          'system' => { 'timezone' => 'Europe/Berlin' },
          'backup' => {
            'destination' => 's3',
            'aws_bucket' => 'my-bucket',
            'aws_access_key_id' => 'AKIA',
            'aws_secret_access_key' => 'secret',
            'aws_region' => 'eu-central-1',
            's3_prefix' => 'solectrus/',
            's3_endpoint_url' => 'https://minio.example.com',
          },
        )
        # with_config_yaml overrides data_path; reseed the dependencies used by start
        File.write(File.join(Rails.configuration.data_path, '.env'), "INFLUX_ADMIN_TOKEN=secret-token\n")
        FileUtils.mkdir_p(File.join(Rails.configuration.data_path, 'helios'))
        allow(BackupRepository::S3).to receive(:client).and_return(s3_client)
      end

      it 'mounts the staging directory as /output and does not forward AWS credentials to the container' do
        allow(BackupRepository::S3::Uploader).to receive(:start_async)

        described_class.start

        run = find_backup_runner_call
        aggregate_failures do
          expect(run).to include('--mount', "type=bind,source=#{host_data_path}/helios/backups-staging,target=/output")
          # The container only ever does the dump+tar work; HELIOS handles
          # every S3 call itself through aws-sdk-s3.
          expect(run.grep(/\AAWS_/)).to be_empty
          expect(run).not_to include('AWS_ACCESS_KEY_ID=AKIA')
        end
      end

      it 'passes only the runner positional args (no destination, no S3 image)' do
        allow(BackupRepository::S3::Uploader).to receive(:start_async)

        described_class.start

        run = find_backup_runner_call
        placeholder_index = run.index('_')
        expect(run[(placeholder_index + 1)..]).to eq(
          ['secret-token', 'solectrus-backup-20260508-143000.tar', '2026-05-08',
           'solectrus-postgresql-1', 'solectrus-influxdb-1'],
        )
      end

      it 'spawns the S3 Uploader after launching the container' do
        allow(BackupRepository::S3::Uploader).to receive(:start_async).and_return(true)

        described_class.start

        expect(BackupRepository::S3::Uploader)
          .to have_received(:start_async).with('solectrus-backup-20260508-143000.tar')
      end
    end
  end

  describe '.in_progress' do
    it 'returns nil when no container exists' do
      state[:docker_inspect_success] = false

      expect(described_class.in_progress).to be_nil
    end

    it 'returns nil when the container exists but is not running' do
      state[:docker_inspect_running] = false

      expect(described_class.in_progress).to be_nil
    end

    it 'returns an InProgress with started_at and filename when running' do
      state[:docker_inspect_started_at] = '2026-05-08T14:30:00.000000000Z'
      state[:docker_inspect_args] = [
        '-c', 'script-body', '_', 'token', 'solectrus-backup-20260508-143000.tar',
        '2026-05-08', 'pg', 'influx'
      ]

      result = described_class.in_progress
      aggregate_failures do
        expect(result).to be_a(BackupRepository::InProgress)
        expect(result.filename).to eq('solectrus-backup-20260508-143000.tar')
        expect(result.started_at).to eq(Time.zone.parse('2026-05-08T14:30:00Z'))
      end
    end

    context 'with a phase marker on disk' do
      before do
        state[:docker_inspect_args] = [
          '-c', 'script-body', '_', 'token', 'solectrus-backup-20260508-143000.tar',
          '2026-05-08', 'pg', 'influx'
        ]
        FileUtils.mkdir_p(File.join(data_path, 'helios', 'runners'))
      end

      it 'enriches the InProgress with the current phase' do
        File.write(File.join(data_path, 'helios', 'runners', 'backup-phase.txt'), "dumping_influx\n")

        expect(described_class.in_progress.phase).to eq(:dumping_influx)
      end

      it 'ignores unknown phase names and falls back to :running' do
        File.write(File.join(data_path, 'helios', 'runners', 'backup-phase.txt'), 'something-else')

        expect(described_class.in_progress.phase).to eq(:running)
      end

      it 'tolerates a missing phase file (window before the first set_phase)' do
        expect(described_class.in_progress.phase).to eq(:running)
      end

      it 'reads the marker from the local runtime dir regardless of destination' do
        with_config_yaml('backup' => { 'destination' => 'external', 'external_path' => '/mnt/nas' })
        FileUtils.mkdir_p(File.join(Rails.configuration.data_path, 'helios', 'runners'))
        File.write(
          File.join(Rails.configuration.data_path, 'helios', 'runners', 'backup-phase.txt'),
          "bundling\n",
        )

        expect(described_class.in_progress.phase).to eq(:bundling)
      end
    end

    context 'when resuming after a HELIOS restart with an S3 destination' do
      let(:filename) { 'solectrus-backup-20260508-143000.tar' }

      before do
        with_config_yaml('backup' => {
                           'destination' => 's3', 'aws_bucket' => 'my-bucket',
                           'aws_access_key_id' => 'AKIA', 'aws_secret_access_key' => 'secret',
                           'aws_region' => 'eu-central-1'
                         })
        # Container is no longer running (it exited before the restart).
        state[:docker_inspect_success] = false
        # Pending marker exists with the filename of the interrupted run.
        BackupRepository::S3.mark_pending!(filename)
        FileUtils.mkdir_p(BackupRepository::S3.directory)
      end

      it 'does not respawn the uploader when no staged tar is present' do
        allow(BackupRepository::S3::Uploader).to receive(:start_async)
        allow(BackupRepository::S3::Uploader).to receive(:current).and_return(nil)

        expect(described_class.in_progress).to be_nil
        expect(BackupRepository::S3::Uploader).not_to have_received(:start_async)
      end

      it 'respawns the uploader when a tar is sitting in staging without a live thread' do
        FileUtils.touch(File.join(BackupRepository::S3.directory, filename))
        allow(BackupRepository::S3::Uploader).to receive(:start_async).and_return(true)
        running_snapshot = BackupRepository::InProgress.new(started_at: Time.current, filename: filename)
        allow(BackupRepository::S3::Uploader).to receive(:current).and_return(nil, running_snapshot)

        result = described_class.in_progress

        expect(BackupRepository::S3::Uploader).to have_received(:start_async).with(filename)
        expect(result).to eq(running_snapshot)
      end
    end
  end

  describe '.unavailable_reason' do
    it 'returns nil when all preconditions are met' do
      expect(described_class.unavailable_reason).to be_nil
    end

    it 'returns a localized reason when the PostgreSQL service is not running' do
      allow(Orchestration::Container).to receive(:find).with('postgresql').and_return(nil)

      expect(described_class.unavailable_reason).to eq(
        I18n.t('backups.runner.unavailable_reasons.postgres_not_running'),
      )
    end

    it 'returns the reason when .env is missing' do
      FileUtils.rm_f(File.join(data_path, '.env'))

      expect(described_class.unavailable_reason).to match(/\.env file is missing/)
    end
  end

  describe '.databases_configured?' do
    def write_compose(*service_names)
      services = service_names.index_with { { 'image' => 'x:1' } }
      File.write(File.join(data_path, 'compose.yaml'), { 'services' => services }.to_yaml)
    end

    it 'is true when both database services exist in compose.yaml' do
      write_compose('postgresql', 'influxdb')

      expect(described_class.databases_configured?).to be(true)
    end

    it 'is false when only one database service exists' do
      write_compose('postgresql')

      expect(described_class.databases_configured?).to be(false)
    end

    it 'is false when compose.yaml does not exist' do
      expect(described_class.databases_configured?).to be(false)
    end
  end

  def find_backup_runner_call
    state[:open3_calls].find { |args| args[0..1] == %w[docker run] && args.include?('helios-backup-runner') }
  end

  def stub_open3_response(args)
    case args
    in ['docker', 'pull', ^(described_class::IMAGE)]
      [state[:docker_pull_output], instance_double(Process::Status, success?: state[:docker_pull_success])]
    in ['docker', 'inspect', 'helios-backup-runner']
      docker_inspect_response
    in ['docker', 'run', *_rest]
      [state[:docker_run_output], instance_double(Process::Status, success?: state[:docker_run_success])]
    else
      raise "Unexpected Open3 call: #{args.inspect}"
    end
  end

  def docker_inspect_response
    success = state[:docker_inspect_success]
    payload = if success
                JSON.generate([{
                                'State' => {
                                  'Running' => state[:docker_inspect_running],
                                  'StartedAt' => state[:docker_inspect_started_at],
                                },
                                'Args' => state[:docker_inspect_args],
                              }])
              else
                ''
              end
    [payload, instance_double(Process::Status, success?: success)]
  end
end
