RSpec.describe 'Import::ConfigurationImporter forecast interval handling' do
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

  context 'with pvnode provider' do
    let(:fc_env) do
      base_env.merge(
        'FORECAST_PROVIDER' => 'pvnode',
        'PVNODE_APIKEY' => 'my-api-key',
        'FORECAST_INTERVAL' => '2',
      )
    end

    it 'drops FORECAST_INTERVAL — pvnode ignores it and schedules pulls itself' do
      expect(importer.result[:forecast]).not_to have_key('forecast_interval')
    end
  end

  context 'with solcast provider' do
    let(:fc_env) do
      base_env.merge(
        'FORECAST_PROVIDER' => 'solcast',
        'SOLCAST_APIKEY' => 'my-api-key',
        'FORECAST_INTERVAL' => '900',
      )
    end

    it 'passes the donor value through unchanged — the operator chooses the cadence' do
      expect(importer.result[:forecast]).to include('forecast_interval' => '900')
    end
  end

  context 'with forecast.solar provider' do
    let(:fc_env) do
      base_env.merge(
        'FORECAST_PROVIDER' => 'forecast.solar',
        'FORECAST_INTERVAL' => '3600',
      )
    end

    it 'passes the donor value through unchanged' do
      expect(importer.result[:forecast]).to include('forecast_interval' => '3600')
    end
  end
end
