RSpec.describe 'Import::ConfigurationImporter solcast site precedence' do
  subject(:importer) { Import::ConfigurationImporter.new(stack_reader) }

  before { with_config_yaml }

  let(:base_env) do
    {
      'FORECAST_PROVIDER' => 'solcast',
      'FORECAST_LATITUDE' => '50.0',
      'FORECAST_LONGITUDE' => '8.0',
      'SOLCAST_APIKEY' => 'my-api-key',
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

  context 'with FORECAST_CONFIGURATIONS=2 and both SOLCAST_SITE + SOLCAST_0_SITE set' do
    # Real-world quirk (user10): donor leaves the legacy SOLCAST_SITE in place
    # while migrating to multi-roof. The forecast-collector reads SOLCAST_0_SITE
    # in multi-roof mode, so that value is the live one.
    let(:fc_env) do
      base_env.merge(
        'FORECAST_CONFIGURATIONS' => '2',
        'FORECAST_0_KWP' => '5.0', 'FORECAST_0_AZIMUTH' => '0', 'FORECAST_0_DECLINATION' => '30',
        'FORECAST_1_KWP' => '3.0', 'FORECAST_1_AZIMUTH' => '90', 'FORECAST_1_DECLINATION' => '20',
        'SOLCAST_SITE' => 'legacy-site',
        'SOLCAST_0_SITE' => 'roof1-site',
        'SOLCAST_1_SITE' => 'roof2-site'
      )
    end

    it 'prefers SOLCAST_0_SITE for roof 1' do
      expect(importer.result[:forecast]).to include(
        'forecast_solcast_id1' => 'roof1-site',
        'forecast_solcast_id2' => 'roof2-site',
      )
    end
  end

  context 'with FORECAST_CONFIGURATIONS=2 and only SOLCAST_SITE set' do
    let(:fc_env) do
      base_env.merge(
        'FORECAST_CONFIGURATIONS' => '2',
        'FORECAST_0_KWP' => '5.0', 'FORECAST_0_AZIMUTH' => '0', 'FORECAST_0_DECLINATION' => '30',
        'FORECAST_1_KWP' => '3.0', 'FORECAST_1_AZIMUTH' => '90', 'FORECAST_1_DECLINATION' => '20',
        'SOLCAST_SITE' => 'legacy-site',
        'SOLCAST_1_SITE' => 'roof2-site'
      )
    end

    it 'falls back to SOLCAST_SITE when SOLCAST_0_SITE is missing' do
      expect(importer.result[:forecast]).to include('forecast_solcast_id1' => 'legacy-site')
    end
  end

  context 'with single roof (FORECAST_CONFIGURATIONS unset) and only SOLCAST_SITE set' do
    let(:fc_env) do
      base_env.merge(
        'FORECAST_KWP' => '5.0', 'FORECAST_AZIMUTH' => '0', 'FORECAST_DECLINATION' => '30',
        'SOLCAST_SITE' => 'legacy-site'
      )
    end

    it 'reads SOLCAST_SITE (canonical for single-roof)' do
      expect(importer.result[:forecast]).to include('forecast_solcast_id1' => 'legacy-site')
    end
  end

  context 'with single roof and only SOLCAST_0_SITE set' do
    let(:fc_env) do
      base_env.merge(
        'FORECAST_KWP' => '5.0', 'FORECAST_AZIMUTH' => '0', 'FORECAST_DECLINATION' => '30',
        'SOLCAST_0_SITE' => 'roof1-site'
      )
    end

    it 'falls back to SOLCAST_0_SITE when the legacy alias is missing' do
      expect(importer.result[:forecast]).to include('forecast_solcast_id1' => 'roof1-site')
    end
  end
end
