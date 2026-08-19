# FORCE_SSL=true means a reverse proxy the user runs themselves terminates TLS
# (Apache, nginx, an external Traefik). Dropping it on import breaks the login
# through that proxy after the first export (issue #416).
RSpec.describe 'Import::ConfigurationImporter dashboard force_ssl' do
  subject(:importer) { Import::ConfigurationImporter.new(stack_reader) }

  before { with_config_yaml }

  let(:dashboard_service) do
    {
      'image' => 'ghcr.io/solectrus/solectrus:latest',
      'ports' => ['3000:3000'],
      'environment' => { 'FORCE_SSL' => force_ssl },
      'labels' => labels,
    }.compact
  end
  let(:labels) { nil }
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

  context 'with FORCE_SSL=true' do
    let(:force_ssl) { 'true' }

    it 'persists the flag' do
      expect(importer.result[:dashboard]).to include('force_ssl' => true)
    end
  end

  context 'with FORCE_SSL=false' do
    let(:force_ssl) { 'false' }

    it 'does not persist the flag' do
      expect(importer.result[:dashboard]).not_to have_key('force_ssl')
    end
  end

  context 'without FORCE_SSL' do
    let(:force_ssl) { nil }

    it 'does not persist the flag' do
      expect(importer.result[:dashboard]).not_to have_key('force_ssl')
    end
  end

  # A HELIOS-managed Traefik terminates TLS itself, so the export derives
  # FORCE_SSL from the reverse-proxy mode and the flag would be redundant.
  context 'with FORCE_SSL=true and an adopted Traefik' do
    let(:force_ssl) { 'true' }
    let(:labels) { { 'traefik.http.routers.dashboard.rule' => 'Host(`solectrus.example.de`)' } }
    let(:services) do
      { 'dashboard' => dashboard_service, 'traefik' => { 'image' => 'traefik:v3.6' } }
    end

    it 'does not persist the flag' do
      expect(importer.result[:reverse_proxy]).to include('app_domain' => 'solectrus.example.de')
      expect(importer.result[:dashboard]).not_to have_key('force_ssl')
    end
  end
end
