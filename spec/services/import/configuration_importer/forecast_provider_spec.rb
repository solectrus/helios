RSpec.describe 'Import::ConfigurationImporter forecast provider' do
  subject(:importer) { Import::ConfigurationImporter.new(stack_reader) }

  before { with_config_yaml }

  let(:base_env) do
    {
      'FORECAST_LATITUDE' => '50.0',
      'FORECAST_LONGITUDE' => '8.0',
      'FORECAST_KWP' => '5.0',
      'FORECAST_AZIMUTH' => '0',
      'FORECAST_DECLINATION' => '30',
    }
  end
  let(:fc_env) { base_env }
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
      raw_env: {},
      raw_compose: { 'services' => services },
      services: services,
      stack_dir: '/srv/solectrus',
    ).tap { |double| allow(double).to receive(:service) { |name| services[name] } }
  end

  context 'when FORECAST_PROVIDER is absent' do
    # Older stacks predate the variable; the forecast-collector itself
    # defaults to forecast.solar. Mirror that so the collector survives
    # the round-trip instead of being dropped on export.
    it 'defaults the provider to forecast.solar' do
      expect(importer.result[:forecast]).to include('forecast' => 'forecast.solar')
    end
  end

  context 'when FORECAST_PROVIDER is set explicitly' do
    let(:fc_env) { base_env.merge('FORECAST_PROVIDER' => 'solcast') }

    it 'keeps the operator-supplied value' do
      expect(importer.result[:forecast]).to include('forecast' => 'solcast')
    end
  end
end
