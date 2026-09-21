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

  context 'when APP_HOST names the machine to itself alone' do
    let(:dashboard_env) { { 'APP_HOST' => 'http://LOCALHOST' } }

    it 'drops it, so the imported stack carries no address its own form refuses' do
      expect(importer.result[:system]).not_to have_key('app_host')
    end
  end

  # The router rule wins over APP_HOST, because it names the address the stack
  # answers on. A rule that names the machine to itself alone answers nothing,
  # so it drops out and leaves APP_HOST its turn.
  context 'when a router rule names the machine to itself alone' do
    let(:dashboard_env) { { 'APP_HOST' => 'solectrus.example.com' } }
    let(:services) do
      {
        'dashboard' => {
          'image' => 'ghcr.io/solectrus/solectrus:latest',
          'environment' => dashboard_env,
          'labels' => { 'traefik.http.routers.dashboard.rule' => 'Host(`localhost`)' },
        },
      }
    end

    it 'keeps the address APP_HOST names' do
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
