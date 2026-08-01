RSpec.describe 'Import::ConfigurationImporter pvnode env vars' do
  subject(:importer) { Import::ConfigurationImporter.new(stack_reader) }

  before { with_config_yaml }

  let(:pvnode_env) do
    {
      'FORECAST_PROVIDER' => 'pvnode',
      'PVNODE_SITE_ID' => 'site-42',
      'PVNODE_APIKEY' => 'pvnode-key',
      'PVNODE_REQUEST_LIMIT' => '750',
    }
  end
  # 'custom-tool' is unmanaged and reads the pvnode credentials as well, so the
  # variables stay referenced by something HELIOS doesn't own. That makes the
  # managed-key list the only thing keeping them out of the leftovers.
  let(:services) do
    {
      'dashboard' => { 'image' => 'ghcr.io/solectrus/solectrus:latest' },
      'forecast-collector' => {
        'image' => 'ghcr.io/solectrus/forecast-collector:latest',
        'environment' => pvnode_env,
      },
      'custom-tool' => {
        'image' => 'example/custom-tool:latest',
        'environment' => pvnode_env.except('FORECAST_PROVIDER'),
      },
    }
  end
  let(:raw_compose) do
    {
      'services' => {
        'dashboard' => { 'image' => 'ghcr.io/solectrus/solectrus:latest' },
        'forecast-collector' => {
          'image' => 'ghcr.io/solectrus/forecast-collector:latest',
          'environment' => pvnode_env.keys,
        },
        'custom-tool' => {
          'image' => 'example/custom-tool:latest',
          'environment' => pvnode_env.except('FORECAST_PROVIDER').keys,
        },
      },
    }
  end
  let(:stack_reader) do
    instance_double(
      Import::StackReader,
      raw_env: pvnode_env,
      raw_compose: raw_compose,
      services: services,
      stack_dir: '/srv/solectrus',
    ).tap { |double| allow(double).to receive(:service) { |name| services[name] } }
  end

  it 'imports the pvnode settings' do
    expect(importer.result[:forecast]).to include(
      'forecast' => 'pvnode',
      'forecast_pvnode_site_id' => 'site-42',
      'forecast_pvnode_apikey' => 'pvnode-key',
      'forecast_pvnode_request_limit' => '750',
    )
  end

  it 'does not surface the pvnode vars as unmanaged leftovers' do
    env_vars = importer.result[:unmanaged]&.dig('env_vars') || {}

    expect(env_vars.keys).not_to include('PVNODE_SITE_ID', 'PVNODE_APIKEY', 'PVNODE_REQUEST_LIMIT')
  end
end
