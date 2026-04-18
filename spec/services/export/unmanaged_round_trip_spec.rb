RSpec.describe 'Unmanaged services round trip (import -> export)' do # rubocop:disable RSpec/DescribeClass
  let(:scenario_path) { Rails.root.join('spec/fixtures/scenarios', scenario) }
  let(:source_compose_path) { scenario_path.join('compose.yaml') }
  let(:source_env_path) { scenario_path.join('.env') }
  let(:stack_reader) { Import::StackReader.new(compose_path: source_compose_path, env_path: source_env_path) }

  before do
    with_config_yaml
    config = Import::ConfigurationImporter.new(stack_reader).import!
    Export::Builder.new(config).write!
  end

  context 'with tibber-collector' do
    let(:scenario) { 'with_tibber' }

    it 'includes tibber-collector in exported compose.yaml' do
      expect(Compose.load.services.names).to include('tibber-collector')
    end

    it 'preserves the tibber-collector image verbatim' do
      tibber = Compose.load.services.find('tibber-collector')
      expect(tibber.image).to eq('ghcr.io/solectrus/tibber-collector:latest')
    end

    it 'preserves the tibber-collector environment block' do
      tibber = Compose.load.services.find('tibber-collector')
      expect(tibber.environment).to include(
        'TIBBER_TOKEN',
        'TIBBER_INTERVAL',
        'INFLUX_HOST=influxdb',
        'INFLUX_MEASUREMENT=${INFLUX_MEASUREMENT_TIBBER}',
      )
    end

    it 'preserves tibber-collector depends_on healthchecks' do
      tibber = Compose.load.services.find('tibber-collector')
      expect(tibber.depends_on).to include('influxdb')
    end

    it 'writes TIBBER_TOKEN verbatim to .env' do
      expect(Env.load['TIBBER_TOKEN']).to eq('tibber-api-token-xyz')
    end

    it 'writes TIBBER_INTERVAL verbatim to .env' do
      expect(Env.load['TIBBER_INTERVAL']).to eq('3600')
    end

    it 'writes INFLUX_MEASUREMENT_TIBBER verbatim to .env' do
      expect(Env.load['INFLUX_MEASUREMENT_TIBBER']).to eq('Tibber')
    end
  end

  context 'with senec-charger' do
    let(:scenario) { 'with_senec_charger' }

    it 'includes senec-charger in exported compose.yaml' do
      expect(Compose.load.services.names).to include('senec-charger')
    end

    it 'preserves the senec-charger image verbatim' do
      charger = Compose.load.services.find('senec-charger')
      expect(charger.image).to eq('ghcr.io/solectrus/senec-charger:latest')
    end

    it 'preserves the senec-charger environment block' do
      charger = Compose.load.services.find('senec-charger')
      expect(charger.environment).to include(
        'CHARGER_INTERVAL',
        'CHARGER_PRICE_MAX',
        'CHARGER_PRICE_TIME_RANGE',
        'CHARGER_FORECAST_THRESHOLD',
        'CHARGER_DRY_RUN',
        'INFLUX_MEASUREMENT_PRICES=Tibber',
        'INFLUX_MEASUREMENT_FORECAST=${INFLUX_MEASUREMENT_FORECAST}',
      )
    end

    it 'preserves shared SENEC variables referenced by the charger' do
      charger = Compose.load.services.find('senec-charger')
      expect(charger.environment).to include('SENEC_HOST', 'SENEC_SCHEMA')
    end

    it 'writes all CHARGER_* env vars verbatim to .env' do
      env = Env.load
      expect(env['CHARGER_INTERVAL']).to eq('3600')
      expect(env['CHARGER_PRICE_MAX']).to eq('70')
      expect(env['CHARGER_PRICE_TIME_RANGE']).to eq('4')
      expect(env['CHARGER_FORECAST_THRESHOLD']).to eq('20')
      expect(env['CHARGER_DRY_RUN']).to eq('false')
    end

    it 'keeps senec-collector (managed) next to senec-charger (unmanaged)' do
      names = Compose.load.services.names
      expect(names).to include('senec-collector', 'senec-charger')
    end

    it 'keeps SENEC_HOST in .env (written by managed senec-collector section)' do
      expect(Env.load['SENEC_HOST']).to eq('192.168.178.42')
    end

    it 'keeps INFLUX_MEASUREMENT_FORECAST in .env (written by managed forecast-collector section)' do
      expect(Env.load['INFLUX_MEASUREMENT_FORECAST']).to eq('Forecast')
    end
  end
end
