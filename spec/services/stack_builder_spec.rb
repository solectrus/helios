RSpec.describe StackBuilder do
  let(:configuration) do
    Configuration.current.tap do |config|
      config.installation_date = '2024-01-15'
      config.timezone = 'Europe/Berlin'
      config.save!
    end
  end

  let(:tmp_dir) { Rails.root.join('tmp/test_stack') }
  let(:compose_path) { tmp_dir.join('compose.yaml') }
  let(:env_path) { tmp_dir.join('.env') }

  before do
    FileUtils.mkdir_p(tmp_dir)
    allow(Rails.configuration).to receive(:helios_stack_path).and_return(
      tmp_dir.to_s,
    )
  end

  after { FileUtils.rm_rf(tmp_dir) }

  describe '#write!' do
    before { described_class.new(configuration).write! }

    it 'creates compose.yaml and .env files' do
      expect(File.exist?(compose_path)).to be true
      expect(File.exist?(env_path)).to be true
    end

    it 'creates data directories' do
      expect(Dir.exist?(tmp_dir.join('postgresql'))).to be true
      expect(Dir.exist?(tmp_dir.join('redis'))).to be true
      expect(Dir.exist?(tmp_dir.join('influxdb'))).to be true
    end
  end

  describe '#compose' do
    it 'returns a Compose::File object' do
      builder = described_class.new(configuration)
      expect(builder.compose).to be_a(Compose::File)
    end
  end

  describe '#env' do
    it 'returns an Env::File object' do
      builder = described_class.new(configuration)
      expect(builder.env).to be_a(Env::File)
    end
  end

  describe 'compose file generation' do
    before { described_class.new(configuration).write! }

    it 'sets project name to solectrus' do
      compose = Compose.load
      expect(compose.name).to eq('solectrus')
    end

    it 'includes all required MVP services' do
      compose = Compose.load
      expect(compose.services.names).to contain_exactly(
        'postgresql',
        'redis',
        'influxdb',
        'dashboard',
      )
    end

    it 'configures postgresql with healthcheck' do
      compose = Compose.load
      postgresql = compose.services.find('postgresql')

      expect(postgresql.image).to eq('postgres:18-alpine')
      expect(postgresql.healthcheck).to include('test', 'interval')
    end

    it 'configures dashboard with depends_on' do
      compose = Compose.load
      dashboard = compose.services.find('dashboard')

      expect(dashboard.depends_on.keys).to include(
        'postgresql',
        'redis',
        'influxdb',
      )
    end

    it 'preserves existing custom services' do
      compose = Compose.load
      compose.add_service('custom-service', image: 'custom:latest')
      compose.save

      described_class.new(configuration).write!

      compose = Compose.load
      expect(compose.services.exists?('custom-service')).to be true
    end
  end

  describe 'env file generation' do
    before { described_class.new(configuration).write! }

    it 'sets user configuration' do
      env = Env.load
      expect(env['INSTALLATION_DATE']).to eq('2024-01-15')
      expect(env['TZ']).to eq('Europe/Berlin')
    end

    it 'generates secrets' do
      env = Env.load
      expect(env['POSTGRES_PASSWORD']).to be_present
      expect(env['INFLUX_PASSWORD']).to be_present
      expect(env['INFLUX_TOKEN']).to be_present
      expect(env['SECRET_KEY_BASE']).to be_present
      expect(env['ADMIN_PASSWORD']).to be_present
    end

    it 'generates secrets with correct lengths' do
      env = Env.load
      expect(env['POSTGRES_PASSWORD'].length).to eq(32)
      expect(env['SECRET_KEY_BASE'].length).to eq(64)
      expect(env['INFLUX_TOKEN'].length).to eq(64)
      expect(env['ADMIN_PASSWORD'].length).to eq(32)
    end

    it 'sets InfluxDB configuration' do
      env = Env.load
      expect(env['INFLUX_ORG']).to eq('solectrus')
      expect(env['INFLUX_BUCKET']).to eq('solectrus')
    end
  end

  describe 'env file generation with existing secrets' do
    before do
      File.write(
        env_path,
        <<~ENV,
          POSTGRES_PASSWORD=existing_password
          # Important comment
          CUSTOM_VAR=custom_value
        ENV
      )
    end

    it 'preserves existing secrets' do
      described_class.new(configuration).write!
      env = Env.load
      expect(env['POSTGRES_PASSWORD']).to eq('existing_password')
    end

    it 'preserves comments' do
      described_class.new(configuration).write!
      content = File.read(env_path)
      expect(content).to include('# Important comment')
    end

    it 'preserves custom variables' do
      described_class.new(configuration).write!
      env = Env.load
      expect(env['CUSTOM_VAR']).to eq('custom_value')
    end

    it 'generates missing secrets' do
      described_class.new(configuration).write!
      env = Env.load
      expect(env['INFLUX_PASSWORD']).to be_present
      expect(env['INFLUX_TOKEN']).to be_present
    end
  end
end
