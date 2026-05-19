RSpec.describe BackupRunner do
  let(:data_path) { Dir.mktmpdir }
  let(:host_data_path) { '/host/data' }
  let(:state) do
    {
      open3_calls: [],
      image_present: true,
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
    allow(RestoreRunner).to receive(:in_progress).and_return(nil)

    allow(Time).to receive(:current).and_return(Time.zone.local(2026, 5, 8, 14, 30, 0))

    allow(Open3).to receive(:capture2e) do |*args|
      state[:open3_calls] << args
      stub_open3_response(args)
    end
  end

  after { FileUtils.remove_entry(data_path) }

  describe '.start' do
    it 'launches docker:cli with the backup script and required mounts' do
      described_class.start

      run = state[:open3_calls].find { |args| args[0..1] == %w[docker run] }
      aggregate_failures do
        expect(run).to include('--name', 'helios-backup-runner')
        expect(run).to include('-v', '/var/run/docker.sock:/var/run/docker.sock')
        expect(run).to include('-v', "#{host_data_path}/helios/backups:/output")
        expect(run).to include('-v', "#{host_data_path}/helios/config.yaml:/config.yaml:ro")
        expect(run).to include('--entrypoint', 'sh', 'docker:cli', '-c')
      end
    end

    it 'passes runtime values as positional shell args (not interpolated)' do
      described_class.start

      run = state[:open3_calls].find { |args| args[0..1] == %w[docker run] }
      placeholder_index = run.index('_')
      expect(run[placeholder_index + 1, 5]).to eq(
        ['secret-token', 'solectrus-backup-20260508-143000.tar', '2026-05-08',
         'solectrus-postgresql-1', 'solectrus-influxdb-1'],
      )
    end

    it 'pulls docker:cli when the image is not present locally' do
      state[:image_present] = false

      described_class.start

      expect(state[:open3_calls]).to include(%w[docker pull docker:cli])
    end

    it 'skips docker pull when the image is already present' do
      described_class.start

      expect(state[:open3_calls]).not_to include(%w[docker pull docker:cli])
    end

    it 'prunes old backups before launching the new container' do
      allow(BackupRepository).to receive(:prune!)

      described_class.start

      expect(BackupRepository).to have_received(:prune!).ordered
    end

    it 'clears a previous error file before launching' do
      FileUtils.mkdir_p(File.join(data_path, 'helios', 'backups'))
      File.write(File.join(data_path, 'helios', 'backups', 'error.txt'), 'old failure')

      described_class.start

      expect(File).not_to exist(File.join(data_path, 'helios', 'backups', 'error.txt'))
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
      allow(RestoreRunner).to receive(:in_progress).and_return(
        BackupRepository::InProgress.new(started_at: Time.zone.now, filename: 'backup.tar.gz'),
      )

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
      state[:image_present] = false
      state[:docker_pull_output] = 'network unreachable'
      state[:docker_pull_success] = false

      expect { described_class.start }.to raise_error(described_class::Error, /network unreachable/)
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
        expect(result.in_progress?).to be(true)
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

  def stub_open3_response(args)
    case args
    in ['docker', 'image', 'inspect', 'docker:cli']
      ['', instance_double(Process::Status, success?: state[:image_present])]
    in ['docker', 'pull', 'docker:cli']
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
