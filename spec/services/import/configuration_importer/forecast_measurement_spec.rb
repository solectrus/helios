RSpec.describe 'Import::ConfigurationImporter forecast measurement' do
  subject(:importer) { Import::ConfigurationImporter.new(stack_reader) }

  before { with_config_yaml }

  let(:base_env) do
    {
      'FORECAST_PROVIDER' => 'forecast.solar',
      'FORECAST_LATITUDE' => '50.0',
      'FORECAST_LONGITUDE' => '8.0',
      'FORECAST_KWP' => '5.0',
      'FORECAST_AZIMUTH' => '0',
      'FORECAST_DECLINATION' => '30',
    }
  end
  let(:fc_env) { base_env }
  let(:raw_env) { {} }
  let(:services) do
    {
      'dashboard' => { 'image' => 'ghcr.io/solectrus/solectrus:latest' },
      'forecast-collector' => {
        'image' => 'ghcr.io/solectrus/forecast-collector:latest',
        'environment' => fc_env,
      },
    }
  end
  let(:stack_reader) do
    instance_double(
      Import::StackReader,
      raw_env: raw_env,
      raw_compose: { 'services' => services },
      services: services,
      stack_dir: '/srv/solectrus',
    ).tap { |double| allow(double).to receive(:service) { |name| services[name] } }
  end

  context 'when INFLUX_MEASUREMENT is set inline on the forecast-collector' do
    let(:fc_env) { base_env.merge('INFLUX_MEASUREMENT' => 'Pvnode') }

    it 'imports the value into forecast.measurement' do
      expect(importer.result[:forecast]).to include('measurement' => 'Pvnode')
    end
  end

  context 'when forecast-collector reads INFLUX_MEASUREMENT via ${INFLUX_MEASUREMENT_FORECAST}' do
    # docker compose config resolves the indirection before serialization, so
    # the service env carries the resolved value.
    let(:fc_env) { base_env.merge('INFLUX_MEASUREMENT' => 'Forecast') }
    let(:raw_env) { { 'INFLUX_MEASUREMENT_FORECAST' => 'Forecast' } }

    it 'imports the resolved value' do
      expect(importer.result[:forecast]).to include('measurement' => 'Forecast')
    end
  end

  context 'when forecast-collector reads INFLUX_MEASUREMENT via a non-canonical var' do
    # Real-world quirk (user8): donor sets FORECAST_INFLUX_MEASUREMENT in .env
    # and bridges with INFLUX_MEASUREMENT=${FORECAST_INFLUX_MEASUREMENT} on the
    # forecast-collector service. Reading the resolved service env recovers the
    # value regardless of which raw .env key the donor used.
    let(:fc_env) { base_env.merge('INFLUX_MEASUREMENT' => 'Forecast') }
    let(:raw_env) { { 'FORECAST_INFLUX_MEASUREMENT' => 'Forecast' } }

    it 'imports the resolved value, not the lowercase default' do
      expect(importer.result[:forecast]).to include('measurement' => 'Forecast')
    end
  end

  context 'when neither service env nor .env defines a measurement' do
    it 'omits measurement so export falls back to the default' do
      expect(importer.result[:forecast]).not_to have_key('measurement')
    end
  end
end
