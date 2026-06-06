RSpec.describe Export::Services::SenecCharger do
  # The charger is only available with a local SENEC battery, dynamic Tibber
  # prices and a running forecast collector — so the base config wires up all
  # three preconditions and lets individual examples knock one out.
  def config_with(senec_charger: { 'interval' => '3600' }, mode: 'full', **overrides)
    Configuration.from_data({
      'deployment' => { 'mode' => mode },
      'system' => { 'timezone' => 'Europe/Berlin' },
      'influxdb' => { 'org' => 'solectrus', 'bucket' => 'solectrus' },
      'senec' => { 'adapter' => 'local' },
      'tibber' => { 'token' => 'abc' },
      'forecast' => { 'forecast' => 'forecast.solar' },
      'sensors' => { 'inverter_power_forecast' => { 'source' => 'forecast', 'measurement' => 'Forecast' } },
      'senec_charger' => senec_charger,
    }.merge(overrides))
  end

  describe '.enabled?' do
    it 'is enabled when all preconditions and a charger section are present' do
      expect(described_class.enabled?(config_with)).to be(true)
    end

    it 'is disabled without a charger section' do
      expect(described_class.enabled?(config_with(senec_charger: {}))).to be(false)
    end

    it 'is disabled without dynamic Tibber prices' do
      expect(described_class.enabled?(config_with(tibber: {}))).to be(false)
    end

    it 'is disabled without a local SENEC battery' do
      expect(described_class.enabled?(config_with(senec: { 'adapter' => 'cloud' }))).to be(false)
    end

    it 'is disabled without a forecast sensor' do
      expect(described_class.enabled?(config_with(sensors: {}))).to be(false)
    end

    it 'is disabled in dashboard_only mode' do
      expect(described_class.enabled?(config_with(mode: 'dashboard_only'))).to be(false)
    end
  end

  describe '#to_h' do
    subject(:service) { described_class.new(config_with).to_h }

    it 'reads with the read-only token and references the prices/forecast measurements' do
      expect(service[:environment]).to include(
        'INFLUX_HOST=influxdb',
        'INFLUX_TOKEN=${INFLUX_TOKEN_READ}',
        'INFLUX_MEASUREMENT_PRICES=${INFLUX_MEASUREMENT_PRICES}',
        'INFLUX_MEASUREMENT_FORECAST=${INFLUX_MEASUREMENT_FORECAST}',
      )
    end

    it 'passes through the SENEC host/schema and the charger tuning vars' do
      expect(service[:environment]).to include(
        'SENEC_HOST', 'SENEC_SCHEMA',
        'CHARGER_INTERVAL', 'CHARGER_PRICE_MAX', 'CHARGER_PRICE_TIME_RANGE',
        'CHARGER_FORECAST_THRESHOLD', 'CHARGER_DRY_RUN'
      )
    end

    it 'never grants write access to InfluxDB' do
      expect(service[:environment]).not_to include('INFLUX_TOKEN=${INFLUX_TOKEN_WRITE}')
    end

    it 'depends on a healthy InfluxDB' do
      expect(service[:depends_on]).to eq(influxdb: { condition: 'service_healthy' })
    end

    it 'defaults to the stable image' do
      expect(service[:image]).to eq('ghcr.io/solectrus/senec-charger:latest')
    end

    it 'honors a chosen develop image channel' do
      config = config_with(senec_charger: { 'interval' => '3600',
                                            'image' => 'ghcr.io/solectrus/senec-charger:develop' })
      expect(described_class.new(config).to_h[:image]).to eq('ghcr.io/solectrus/senec-charger:develop')
    end
  end

  describe Export::Env::SenecCharger do
    def env_for(**)
      env_file = Env::File.new(File::NULL)
      described_class.new(env_file, config_with(**)).call
      env_file.to_s
    end

    it 'emits the charger tuning vars with the user values' do
      result = env_for(senec_charger: {
                         'interval' => '900', 'price_max' => '80', 'price_time_range' => '6',
                         'forecast_threshold' => '15', 'dry_run' => 'true'
                       })
      expect(result).to include(
        'CHARGER_INTERVAL=900', 'CHARGER_PRICE_MAX=80', 'CHARGER_PRICE_TIME_RANGE=6',
        'CHARGER_FORECAST_THRESHOLD=15', 'CHARGER_DRY_RUN=true'
      )
    end

    it 'falls back to the collector defaults for blank values' do
      expect(env_for(senec_charger: { 'interval' => '3600' })).to include(
        'CHARGER_INTERVAL=3600', 'CHARGER_PRICE_MAX=70', 'CHARGER_PRICE_TIME_RANGE=4',
        'CHARGER_FORECAST_THRESHOLD=20', 'CHARGER_DRY_RUN=false'
      )
    end

    it 'emits nothing when the charger is unavailable' do
      expect(env_for(tibber: {})).not_to include('CHARGER_')
    end
  end
end
