RSpec.describe 'Import::ConfigurationImporter app_host handling' do
  subject(:importer) { Import::ConfigurationImporter.new(stack_reader) }

  before { with_config_yaml }

  let(:services) do
    {
      'dashboard' => {
        'image' => 'ghcr.io/solectrus/solectrus:latest',
        'environment' => dashboard_env,
      },
    }
  end
  let(:dashboard_env) { {} }
  let(:stack_reader) do
    instance_double(
      Import::StackReader,
      raw_env: {},
      raw_compose: { 'services' => services },
      services: services,
      stack_dir: '/srv/solectrus',
    ).tap { |double| allow(double).to receive(:service) { |name| services[name] } }
  end

  context 'when APP_HOST is a bare hostname' do
    let(:dashboard_env) { { 'APP_HOST' => 'solectrus.example.com' } }

    it 'imports it unchanged' do
      expect(importer.result[:system]).to include('app_host' => 'solectrus.example.com')
    end
  end

  context 'when APP_HOST is a bare IP' do
    let(:dashboard_env) { { 'APP_HOST' => '192.168.1.10' } }

    it 'imports it unchanged' do
      expect(importer.result[:system]).to include('app_host' => '192.168.1.10')
    end
  end

  context 'when the user accidentally prefixed APP_HOST with http://' do
    let(:dashboard_env) { { 'APP_HOST' => 'http://solectrus.intern.example.de' } }

    it 'strips the scheme so config.yaml stores the bare hostname' do
      expect(importer.result[:system]).to include('app_host' => 'solectrus.intern.example.de')
    end
  end

  context 'when APP_HOST starts with https://' do
    let(:dashboard_env) { { 'APP_HOST' => 'https://solectrus.example.com' } }

    it 'strips the scheme' do
      expect(importer.result[:system]).to include('app_host' => 'solectrus.example.com')
    end
  end

  context 'when APP_HOST is missing entirely' do
    let(:dashboard_env) { {} }

    it 'leaves app_host unset rather than storing an empty string' do
      expect(importer.result[:system]).not_to have_key('app_host')
    end
  end
end
