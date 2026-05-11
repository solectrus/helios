RSpec.describe 'Import::ConfigurationImporter dashboard host_port' do
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
end
