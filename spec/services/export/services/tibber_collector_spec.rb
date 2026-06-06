RSpec.describe Export::Services::TibberCollector do
  def config_with(tibber:, mode: 'full')
    Configuration.from_data(
      'deployment' => { 'mode' => mode },
      'system' => { 'timezone' => 'Europe/Berlin' },
      'influxdb' => { 'org' => 'solectrus', 'bucket' => 'solectrus' },
      'tibber' => tibber,
    )
  end

  describe '.enabled?' do
    it 'is enabled once a token is configured' do
      config = config_with(tibber: { 'token' => 'abc' })
      expect(described_class.enabled?(config)).to be(true)
    end

    it 'is disabled without a token' do
      config = config_with(tibber: { 'measurement' => 'Prices' })
      expect(described_class.enabled?(config)).to be(false)
    end

    # Mirrors the forecast-collector: fetching a public API needs no local
    # hardware, so it runs alongside a dashboard_only stack.
    it 'stays enabled in dashboard_only mode' do
      config = config_with(tibber: { 'token' => 'abc' }, mode: 'dashboard_only')
      expect(described_class.enabled?(config)).to be(true)
    end
  end

  describe '#to_h' do
    it 'maps the generic measurement var to the canonical prices key and writes to influxdb directly' do
      config = config_with(tibber: { 'token' => 'abc' })
      service = described_class.new(config).to_h

      expect(service[:environment]).to include(
        'TIBBER_TOKEN',
        'INFLUX_MEASUREMENT=${INFLUX_MEASUREMENT_PRICES}',
        'INFLUX_TOKEN=${INFLUX_TOKEN_WRITE}',
      )
      # The poll cadence stays at the collector's own default.
      expect(service[:environment]).not_to include('TIBBER_INTERVAL')
      expect(service[:depends_on]).to eq(influxdb: { condition: 'service_healthy' })
    end

    it 'defaults to the stable image' do
      config = config_with(tibber: { 'token' => 'abc' })
      expect(described_class.new(config).to_h[:image]).to eq('ghcr.io/solectrus/tibber-collector:latest')
    end

    it 'honors a chosen develop image channel' do
      config = config_with(tibber: { 'token' => 'abc', 'image' => 'ghcr.io/solectrus/tibber-collector:develop' })
      expect(described_class.new(config).to_h[:image]).to eq('ghcr.io/solectrus/tibber-collector:develop')
    end
  end

  describe Export::Env::Tibber do
    def env_for(tibber)
      env_file = Env::File.new(File::NULL)
      described_class.new(env_file, config_with(tibber:)).call
      env_file.to_s
    end

    it 'emits the token and the prices measurement, defaulting to Prices' do
      expect(env_for('token' => 'abc')).to include('TIBBER_TOKEN=abc', 'INFLUX_MEASUREMENT_PRICES=Prices')
    end

    it 'honors a custom measurement' do
      expect(env_for('token' => 'abc', 'measurement' => 'Tibber')).to include('INFLUX_MEASUREMENT_PRICES=Tibber')
    end

    it 'emits nothing without a token' do
      expect(env_for('measurement' => 'Prices')).not_to include('TIBBER')
    end
  end
end
