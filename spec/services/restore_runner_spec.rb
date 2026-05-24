require 'rubygems/package'

RSpec.describe RestoreRunner do
  let(:data_path) { Dir.mktmpdir }
  let(:host_data_path) { '/host/data' }
  let(:filename) { 'solectrus-backup-20260508-110000.tar' }
  let(:state) do
    {
      open3_calls: [],
      image_present: true,
      docker_run_output: 'container-id',
      docker_run_success: true,
      docker_pull_output: '',
      docker_pull_success: true,
      docker_inspect_success: false,
      docker_inspect_running: false,
      docker_inspect_started_at: '2026-05-08T14:30:00Z',
      docker_inspect_args: ['-c', 'script'],
    }
  end

  before do
    allow(Rails.configuration).to receive(:data_path).and_return(data_path)
    FileUtils.mkdir_p(File.join(data_path, 'helios', 'backups'))
    File.write(File.join(data_path, '.env'), "INFLUX_ADMIN_TOKEN=secret-token\n")
    File.binwrite(
      File.join(data_path, 'helios', 'backups', filename),
      tar_archive(
        'helios/config.yaml' => restored_config_yaml,
        'solectrus-postgresql-backup-2026-05-08.sql.gz' => 'postgres dump',
        'solectrus-influxdb-backup-2026-05-08.tar.gz' => 'influx backup',
      ),
    )

    allow(BackupRepository).to receive(:find!).with(filename).and_return(
      Backup.new(
        filename:,
        bytes: 7,
        created_at: Time.zone.local(2026, 5, 8, 11, 0, 0),
        destination: 'local',
        files: [],
      ),
    )
    allow(Export::Builder).to receive(:new).and_return(instance_double(Export::Builder, write!: nil))
    allow(BackupRunner).to receive(:running?).and_return(false)
    allow(Orchestration::Runner).to receive(:host_data_path).and_return(host_data_path)
    allow(Compose).to receive(:load).and_return(
      instance_double(
        Compose::File,
        services: instance_double(
          Compose::ServiceCollection,
          names: %w[helios postgresql influxdb dashboard senec-collector forecast-collector],
        ),
      ),
    )
    allow(Orchestration::Container).to receive(:all).and_return(
      [
        mock_container('solectrus-postgresql-1', 'postgresql', running: true),
        mock_container('solectrus-influxdb-1', 'influxdb', running: true),
        mock_container('solectrus-helios-1', 'helios', running: true),
        mock_container('solectrus-dashboard-1', 'dashboard', running: true),
        mock_container('solectrus-senec-collector-1', 'senec-collector', running: true),
        mock_container('solectrus-forecast-collector-1', 'forecast-collector', running: false),
      ],
    )

    allow(Open3).to receive(:capture2e) do |*args|
      state[:open3_calls] << args
      stub_open3_response(args)
    end
  end

  after { FileUtils.remove_entry(data_path) }

  describe '.start' do
    it 'writes the restored config from the archive before starting the restore helper' do
      described_class.start(filename)

      config = Configuration.load_file(Configuration.path)
      expect(config.dig('postgresql', 'image')).to eq('postgres:18-alpine')
      expect(Export::Builder).to have_received(:new).with(Configuration.current)
    end

    it 'launches docker:cli with the restore script and required mounts' do
      described_class.start(filename)

      run = state[:open3_calls].find { |args| args[0..1] == %w[docker run] }
      aggregate_failures do
        expect(run).to include('--name', 'helios-restore-runner')
        expect(run).to include('-v', '/var/run/docker.sock:/var/run/docker.sock')
        expect(run).to include('-v', "#{host_data_path}/helios/backups:/output")
        expect(run).to include('-v', "#{host_data_path}:/data")
        expect(run).to include('-v', "#{host_data_path}:#{host_data_path}")
        expect(run).to include('--entrypoint', 'sh', described_class::IMAGE, '-c')
      end
    end

    it 'passes runtime values as positional shell args' do
      described_class.start(filename)

      run = state[:open3_calls].find { |args| args[0..1] == %w[docker run] }
      placeholder_index = run.index('_')
      expect(run[placeholder_index + 1, 9]).to eq(
        [
          'secret-token', filename, host_data_path, "#{host_data_path}/postgresql",
          "#{host_data_path}/influxdb", "#{host_data_path}/redis", '0',
          'postgresql influxdb dashboard senec-collector forecast-collector',
          'compose.yaml'
        ],
      )
    end

    it 'passes the actual compose filename when the user uses compose.yml' do
      File.write(File.join(data_path, 'compose.yml'), "services: {}\n")

      described_class.start(filename)

      run = state[:open3_calls].find { |args| args[0..1] == %w[docker run] }
      placeholder_index = run.index('_')
      expect(run[placeholder_index + 9]).to eq('compose.yml')
    end

    it 'passes restart-after flag "1" when every configured service has a running container' do
      allow(Orchestration::Container).to receive(:all).and_return(
        [
          mock_container('solectrus-postgresql-1', 'postgresql', running: true),
          mock_container('solectrus-influxdb-1', 'influxdb', running: true),
          mock_container('solectrus-helios-1', 'helios', running: true),
          mock_container('solectrus-dashboard-1', 'dashboard', running: true),
          mock_container('solectrus-senec-collector-1', 'senec-collector', running: true),
          mock_container('solectrus-forecast-collector-1', 'forecast-collector', running: true),
        ],
      )

      described_class.start(filename)

      run = state[:open3_calls].find { |args| args[0..1] == %w[docker run] }
      placeholder_index = run.index('_')
      expect(run[placeholder_index + 7]).to eq('1')
    end

    it 'passes restart-after flag "0" when a configured service has no container at all' do
      allow(Orchestration::Container).to receive(:all).and_return(
        [
          mock_container('solectrus-postgresql-1', 'postgresql', running: true),
          mock_container('solectrus-influxdb-1', 'influxdb', running: true),
        ],
      )

      described_class.start(filename)

      run = state[:open3_calls].find { |args| args[0..1] == %w[docker run] }
      placeholder_index = run.index('_')
      expect(run[placeholder_index + 7]).to eq('0')
    end

    it 'tears down via compose down -v (without helios), wipes data, starts DBs, then conditionally restarts' do
      described_class.start(filename)

      run = state[:open3_calls].find { |args| args[0..1] == %w[docker run] }
      script = run[run.index('-c') + 1]
      aggregate_failures do
        expect(script).to include('compose down -v --remove-orphans $SERVICES > "$STOP_LOG" 2>&1')
        expect(script).to include('rm -rf "$POSTGRES_DATA_PATH" "$INFLUXDB_DATA_PATH" "$REDIS_DATA_PATH"')
        expect(script).to include('compose up --no-build --wait -d postgresql influxdb > "$DB_START_LOG" 2>&1')
        expect(script).to include('docker compose -f "$COMPOSE_PATH"')
        expect(script).to include('--project-directory "$HOST_DATA_PATH"')
        expect(script).to include('if [ "$RESTART_AFTER" = "1" ]; then')
        expect(script).to include('compose up --no-build -d $SERVICES > "$START_LOG" 2>&1')
      end
    end

    it 'never lists helios in the services arg passed to compose down/up' do
      described_class.start(filename)

      run = state[:open3_calls].find { |args| args[0..1] == %w[docker run] }
      placeholder_index = run.index('_')
      services_arg = run[placeholder_index + 8]
      expect(services_arg.split).not_to include('helios')
    end

    it 'restores InfluxDB through the local container HTTP endpoint' do
      described_class.start(filename)

      run = state[:open3_calls].find { |args| args[0..1] == %w[docker run] }
      script = run[run.index('-c') + 1]
      expect(script).to include('influx restore --full --host http://localhost:8086 \\')
      expect(script).to include('-t "$TOKEN" --operator-token "$TOKEN" "$1"')
    end

    it 'reports PostgreSQL restore command output on failure' do
      described_class.start(filename)

      run = state[:open3_calls].find { |args| args[0..1] == %w[docker run] }
      script = run[run.index('-c') + 1]
      aggregate_failures do
        expect(script).to include('psql -v ON_ERROR_STOP=1 -h 127.0.0.1 -U postgres')
        expect(script).to include('POSTGRES_RESTORE_LOG="$WORK_DIR/postgresql-restore.log"')
        expect(script).to include('> "$POSTGRES_RESTORE_LOG" 2>&1')
        expect(script).to include('PostgreSQL restore failed: $(tail -n 20 "$POSTGRES_RESTORE_LOG"')
      end
    end

    it 'creates solectrus_production before importing the PostgreSQL dump' do
      described_class.start(filename)

      run = state[:open3_calls].find { |args| args[0..1] == %w[docker run] }
      script = run[run.index('-c') + 1]
      aggregate_failures do
        expect(script).to include("SELECT 1 FROM pg_database WHERE datname='solectrus_production'")
        expect(script).to include('CREATE DATABASE solectrus_production')
        expect(script.index('CREATE DATABASE solectrus_production')).to be < script.index('PostgreSQL restore failed')
      end
    end

    it 'pulls docker:cli when the image is not present locally' do
      state[:image_present] = false

      described_class.start(filename)

      expect(state[:open3_calls]).to include(['docker', 'pull', described_class::IMAGE])
    end

    it 'clears previous backup and restore errors before launching' do
      File.write(File.join(data_path, 'helios', 'backups', 'error.txt'), 'backup failure')
      File.write(File.join(data_path, 'helios', 'backups', 'restore-error.txt'), 'restore failure')

      described_class.start(filename)

      expect(File).not_to exist(File.join(data_path, 'helios', 'backups', 'error.txt'))
      expect(File).not_to exist(File.join(data_path, 'helios', 'backups', 'restore-error.txt'))
    end

    it 'raises when a backup is already running' do
      allow(BackupRunner).to receive(:running?).and_return(true)

      expect { described_class.start(filename) }.to raise_error(described_class::Error, /backup is already/)
    end

    it 'raises when a restore is already running' do
      state[:docker_inspect_success] = true
      state[:docker_inspect_running] = true

      expect { described_class.start(filename) }.to raise_error(described_class::Error, /restore is already/)
    end

    it 'raises when the backup is unknown' do
      allow(BackupRepository).to receive(:find!).with(filename).and_raise(BackupRepository::NotFound)

      expect { described_class.start(filename) }.to raise_error(described_class::Error, /not found/)
    end

    it 'raises when the archive is missing expected content' do
      File.binwrite(
        File.join(data_path, 'helios', 'backups', filename),
        tar_archive('helios/config.yaml' => restored_config_yaml),
      )

      expect { described_class.start(filename) }.to raise_error(
        described_class::Error,
        I18n.t('backups.restorer.errors.missing_postgres'),
      )
    end

    it 'accepts archives whose entries are prefixed with ./ as produced by tar -C dir .' do
      File.binwrite(
        File.join(data_path, 'helios', 'backups', filename),
        tar_archive(
          './helios/config.yaml' => restored_config_yaml,
          './solectrus-postgresql-backup-2026-05-08.sql.gz' => 'postgres dump',
          './solectrus-influxdb-backup-2026-05-08.tar.gz' => 'influx backup',
        ),
      )

      expect { described_class.start(filename) }.not_to raise_error
    end

    it 'translates a docker name conflict into a friendly error' do
      state[:docker_inspect_success] = false
      state[:docker_run_output] = 'docker: container name "/helios-restore-runner" is already in use'
      state[:docker_run_success] = false

      expect { described_class.start(filename) }.to raise_error(described_class::Error, /already in progress/)
    end

    context 'with S3 destination' do
      let(:s3_client) { Aws::S3::Client.new(stub_responses: true, region: 'eu-central-1') }

      before do
        with_config_yaml('backup' => {
                           'destination' => 's3', 'aws_bucket' => 'my-bucket',
                           'aws_access_key_id' => 'AKIA', 'aws_secret_access_key' => 'secret',
                           'aws_region' => 'eu-central-1'
                         })
        # with_config_yaml overrides data_path; re-seed deps used by start.
        File.write(File.join(Rails.configuration.data_path, '.env'), "INFLUX_ADMIN_TOKEN=secret-token\n")
        FileUtils.mkdir_p(BackupRepository::S3.directory)
        File.binwrite(
          File.join(BackupRepository::S3.directory, filename),
          tar_archive(
            'helios/config.yaml' => restored_config_yaml,
            'solectrus-postgresql-backup-2026-05-08.sql.gz' => 'postgres dump',
            'solectrus-influxdb-backup-2026-05-08.tar.gz' => 'influx backup',
          ),
        )
        allow(BackupRepository).to receive(:find!).with(filename).and_return(
          Backup.new(filename:, bytes: 7, created_at: Time.zone.local(2026, 5, 8, 11, 0, 0),
                     destination: 's3', files: []),
        )
        allow(BackupRepository::S3).to receive(:client).and_return(s3_client)
        s3_client.stub_responses(:get_object, body: tar_archive(
          'helios/config.yaml' => restored_config_yaml,
          'solectrus-postgresql-backup-2026-05-08.sql.gz' => 'postgres dump',
          'solectrus-influxdb-backup-2026-05-08.tar.gz' => 'influx backup',
        ))
      end

      it 'hands the run to the Downloader, which kicks off the container on completion' do
        allow(BackupRepository::S3::Downloader).to receive(:start_async)

        described_class.start(filename)

        expect(BackupRepository::S3::Downloader)
          .to have_received(:start_async).with(filename)
      end

      it 'does not start the docker container synchronously (the Downloader will)' do
        allow(BackupRepository::S3::Downloader).to receive(:start_async)

        described_class.start(filename)

        expect(state[:open3_calls].any? { |args| args[0..1] == %w[docker run] }).to be(false)
      end

      it 'still pulls the docker image up-front so the Downloader does not hit a cold cache later' do
        allow(BackupRepository::S3::Downloader).to receive(:start_async)
        state[:image_present] = false

        described_class.start(filename)

        expect(state[:open3_calls]).to include(['docker', 'pull', described_class::IMAGE])
      end
    end
  end

  describe '.in_progress' do
    it 'returns nil when no container exists' do
      state[:docker_inspect_success] = false

      expect(described_class.in_progress).to be_nil
    end

    it 'returns an InProgress with started_at and filename when running' do
      state[:docker_inspect_success] = true
      state[:docker_inspect_running] = true
      state[:docker_inspect_args] = [
        '-c', 'script-body', '_', 'token', filename, 'pg', 'influx', 'helios', 'dashboard'
      ]

      result = described_class.in_progress
      aggregate_failures do
        expect(result).to be_a(BackupRepository::InProgress)
        expect(result.filename).to eq(filename)
        expect(result.started_at).to eq(Time.zone.parse('2026-05-08T14:30:00Z'))
      end
    end
  end

  def stub_open3_response(args)
    case args
    in ['docker', 'image', 'inspect', ^(described_class::IMAGE)]
      ['', instance_double(Process::Status, success?: state[:image_present])]
    in ['docker', 'pull', ^(described_class::IMAGE)]
      [state[:docker_pull_output], instance_double(Process::Status, success?: state[:docker_pull_success])]
    in ['docker', 'inspect', 'helios-restore-runner']
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

  def restored_config_yaml
    <<~YAML
      postgresql:
        image: postgres:18-alpine
        password: restored-secret
      influxdb:
        image: influxdb:2-alpine
        org: solectrus
        bucket: solectrus
        password: restored-secret
        token_admin: restored-token
        token_readwrite: restored-token
        token_write: restored-token
        token_read: restored-token
      system:
        timezone: Europe/Berlin
    YAML
  end

  def mock_container(name, service_name, running:)
    instance_double(Orchestration::Container, name: name, service_name: service_name, running?: running)
  end

  def tar_archive(entries)
    StringIO.new.tap do |io|
      Gem::Package::TarWriter.new(io) do |tar|
        entries.each do |name, content|
          tar.add_file_simple(name, 0o644, content.bytesize) { |entry| entry.write(content) }
        end
      end
    end.string
  end
end
