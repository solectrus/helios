RSpec.describe 'Import::ConfigurationImporter dashboard' do
  subject(:importer) { Import::ConfigurationImporter.new(stack_reader) }

  before { with_config_yaml }

  let(:services) { { 'dashboard' => dashboard_service } }
  let(:stack_reader) do
    instance_double(
      Import::StackReader,
      raw_env: {},
      raw_compose: { 'services' => services },
      services: services,
      stack_dir: '/srv/solectrus',
    ).tap { |double| allow(double).to receive(:service) { |name| services[name] } }
  end

  context 'with the canonical 3000:3000 mapping' do
    let(:dashboard_service) do
      { 'image' => 'ghcr.io/solectrus/solectrus:latest', 'ports' => ['3000:3000'] }
    end

    it 'does not persist host_port (HELIOS default applies)' do
      expect(importer.result[:dashboard]).not_to have_key('host_port')
    end
  end

  context 'with a remapped host port (3010:3000)' do
    let(:dashboard_service) do
      { 'image' => 'ghcr.io/solectrus/solectrus:latest', 'ports' => ['3010:3000'] }
    end

    it 'preserves the host_port' do
      expect(importer.result[:dashboard]).to include('host_port' => '3010')
    end
  end

  # `docker compose config --format json` normalizes short-form ports into
  # long-form hashes. Confirm we read host_port out of either shape.
  context 'with long-form port mapping' do
    let(:dashboard_service) do
      {
        'image' => 'ghcr.io/solectrus/solectrus:latest',
        'ports' => [{ 'target' => 3000, 'published' => '3010', 'protocol' => 'tcp' }],
      }
    end

    it 'preserves the host_port' do
      expect(importer.result[:dashboard]).to include('host_port' => '3010')
    end
  end

  context 'without a dashboard ports block (Traefik-fronted stack)' do
    let(:dashboard_service) do
      { 'image' => 'ghcr.io/solectrus/solectrus:latest' }
    end

    it 'does not persist host_port' do
      expect(importer.result[:dashboard]).not_to have_key('host_port')
    end
  end

  # `docker compose config` reports a variable it passes through without a
  # value as nil, and an empty one from .env as an empty string. The empty one
  # turns the lookup off, so it must survive as a value of its own.
  describe 'NOMINATIM_URL' do
    let(:dashboard_service) do
      { 'image' => 'ghcr.io/solectrus/solectrus:latest', 'environment' => environment }
    end
    let(:dashboard) { importer.result[:dashboard] }

    {
      'it is empty' => [' ', ''],
      'it names a server' => [' http://192.168.1.10:8080', 'http://192.168.1.10:8080'],
    }.each do |situation, (value, stored)|
      context "when #{situation}" do
        let(:environment) { { 'NOMINATIM_URL' => value } }

        it 'keeps the value' do
          expect(dashboard).to include('nominatim_url' => stored)
        end
      end
    end

    {
      'the dashboard does not receive it' => {},
      'it is passed through but defined nowhere' => { 'NOMINATIM_URL' => nil },
    }.each do |situation, env|
      context "when #{situation}" do
        let(:environment) { env }

        it 'keeps the public server' do
          expect(dashboard).not_to have_key('nominatim_url')
        end
      end
    end
  end
end
