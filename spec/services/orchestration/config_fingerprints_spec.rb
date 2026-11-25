RSpec.describe Orchestration::ConfigFingerprints do
  let(:path) { described_class.path }
  let(:services) do
    {
      'dashboard' => {
        'image' => 'ghcr.io/solectrus/solectrus:latest',
        'environment' => { 'ADMIN_PASSWORD' => 's3cret', 'INFLUX_SENSOR_HOUSE_POWER' => 'SENEC:house_power' },
        'ports' => [{ 'target' => 3000 }],
      },
      'redis' => { 'image' => 'redis:8-alpine' },
    }
  end

  before do
    FileUtils.rm_f(path)
    allow(Orchestration::Runner).to receive(:config_services) { services }
  end

  after { FileUtils.rm_f(path) }

  def stored
    JSON.parse(File.read(path))
  end

  describe '.sync!' do
    it 'fingerprints each service that runs its deployed config' do
      described_class.sync!({ 'dashboard' => 'h1', 'redis' => 'h2' }, { 'dashboard' => 'h1', 'redis' => 'h2' })

      expect(stored.keys).to contain_exactly('dashboard', 'redis')
      expect(stored['dashboard']).to include('hash' => 'h1')
      expect(stored.dig('dashboard', 'parts').keys).to contain_exactly('image', 'ports')
    end

    it 'keeps the values out of the file' do
      described_class.sync!({ 'dashboard' => 'h1' }, { 'dashboard' => 'h1' })

      expect(File.read(path)).not_to include('s3cret')
      expect(stored.dig('dashboard', 'environment').keys).to contain_exactly(
        'ADMIN_PASSWORD',
        'INFLUX_SENSOR_HOUSE_POWER',
      )
    end

    it 'skips a service whose config moved on since the deploy' do
      described_class.sync!({ 'dashboard' => 'old', 'redis' => 'h2' }, { 'dashboard' => 'new', 'redis' => 'h2' })

      expect(stored.keys).to eq(['redis'])
    end

    it 'skips a deployed service that compose no longer lists' do
      described_class.sync!({ 'gone' => 'h9' }, { 'gone' => 'h9' })

      expect(stored).to eq({})
    end

    it 'leaves a current fingerprint alone and does not ask compose' do
      described_class.sync!({ 'redis' => 'h2' }, { 'redis' => 'h2' })
      before = stored
      services['redis']['image'] = 'redis:9-alpine'

      described_class.sync!({ 'redis' => 'h2' }, { 'redis' => 'h2' })

      expect(stored).to eq(before)
      expect(Orchestration::Runner).to have_received(:config_services).once
    end

    it 'drops the fingerprints of services no longer deployed' do
      described_class.sync!({ 'dashboard' => 'h1', 'redis' => 'h2' }, { 'dashboard' => 'h1', 'redis' => 'h2' })
      described_class.sync!({ 'redis' => 'h3' }, { 'redis' => 'h3' })

      expect(stored.keys).to eq(['redis'])
    end

    it 'reads compose afresh even when a comparison cached it' do
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
      described_class.sync!({ 'redis' => 'h2' }, { 'redis' => 'h2' })
      described_class.change('redis', 'h2')
      services['redis']['image'] = 'redis:9-alpine'

      described_class.sync!({ 'redis' => 'h3' }, { 'redis' => 'h3' })

      expect(stored.dig('redis', 'parts', 'image')).to eq(Digest::SHA256.hexdigest('redis:9-alpine'.to_json))
    end

    it 'logs a failing compose call instead of raising' do
      allow(Orchestration::Runner).to receive(:config_services).and_raise(
        Orchestration::Runner::CommandError, 'boom'
      )

      expect { described_class.sync!({ 'redis' => 'h2' }, { 'redis' => 'h2' }) }.not_to raise_error
      expect(File.exist?(path)).to be(false)
    end
  end

  describe '.change' do
    before { described_class.sync!({ 'dashboard' => 'h1' }, { 'dashboard' => 'h1' }) }

    it 'names added, removed and changed variables' do
      env = services['dashboard']['environment']
      env['ADMIN_PASSWORD'] = 'n3w'
      env.delete('INFLUX_SENSOR_HOUSE_POWER')
      env['INFLUX_SENSOR_INVERTER_POWER_FORECAST_MIN'] = 'Forecast:watt_min'

      change = described_class.change('dashboard', 'h1')

      expect(change.added).to eq(['INFLUX_SENSOR_INVERTER_POWER_FORECAST_MIN'])
      expect(change.removed).to eq(['INFLUX_SENSOR_HOUSE_POWER'])
      expect(change.changed).to eq(['ADMIN_PASSWORD'])
      expect(change.parts).to be_empty
    end

    it 'flags a new image as a changed part' do
      services['dashboard']['image'] = 'ghcr.io/solectrus/solectrus:develop'

      expect(described_class.change('dashboard', 'h1').parts).to eq(['image'])
    end

    it 'flags a change outside the variables' do
      services['dashboard']['ports'] = [{ 'target' => 3001 }]

      change = described_class.change('dashboard', 'h1')

      expect([change.added, change.removed, change.changed]).to all(be_empty)
      expect(change.parts).to eq(['ports'])
    end

    it 'ignores the key order of compose output' do
      services['dashboard']['ports'] = [{ 'target' => 3000 }]
      services['dashboard'] = services['dashboard'].to_a.reverse.to_h

      expect(described_class.change('dashboard', 'h1')).to be_nil
    end

    it 'is nil when nothing it compares differs' do
      expect(described_class.change('dashboard', 'h1')).to be_nil
    end

    it 'is nil when the fingerprint belongs to another deploy' do
      services['dashboard']['image'] = 'ghcr.io/solectrus/solectrus:develop'

      expect(described_class.change('dashboard', 'h0')).to be_nil
    end

    it 'is nil for a service without a fingerprint' do
      expect(described_class.change('redis', 'h2')).to be_nil
    end

    it 'is nil when compose no longer lists the service' do
      services.delete('dashboard')

      expect(described_class.change('dashboard', 'h1')).to be_nil
    end

    it 'is nil when compose fails' do
      allow(Orchestration::Runner).to receive(:config_services).and_raise(
        Orchestration::Runner::CommandError, 'boom'
      )

      expect(described_class.change('dashboard', 'h1')).to be_nil
    end
  end

  describe '.load_file' do
    it 'treats a corrupt file as empty' do
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, '{not json')

      expect(described_class.load_file).to eq({})
    end
  end
end
