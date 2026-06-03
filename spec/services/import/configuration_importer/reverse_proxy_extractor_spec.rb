RSpec.describe 'Import::ConfigurationImporter reverse_proxy bind_ip' do
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

  # `docker compose config --format json` resolves a bound port into a long-form
  # hash with `host_ip`; the short-form `ip:host:container` is the raw fallback.
  context 'with a host-IP-bound published port (long form)' do
    let(:dashboard_service) do
      {
        'image' => 'ghcr.io/solectrus/solectrus:latest',
        'ports' => [{ 'host_ip' => '10.0.0.5', 'target' => 3000, 'published' => '3000', 'protocol' => 'tcp' }],
      }
    end

    it 'captures bind_ip on reverse_proxy' do
      expect(importer.result[:reverse_proxy]).to include('bind_ip' => '10.0.0.5')
    end
  end

  context 'with a host-IP-bound published port (short form)' do
    let(:dashboard_service) do
      { 'image' => 'ghcr.io/solectrus/solectrus:latest', 'ports' => ['10.0.0.5:3000:3000'] }
    end

    it 'captures bind_ip' do
      expect(importer.result[:reverse_proxy]).to include('bind_ip' => '10.0.0.5')
    end
  end

  context 'with a wildcard bind (0.0.0.0)' do
    let(:dashboard_service) do
      { 'image' => 'ghcr.io/solectrus/solectrus:latest', 'ports' => ['0.0.0.0:3000:3000'] }
    end

    it 'does not set bind_ip (wildcard == HELIOS default)' do
      expect(importer.result[:reverse_proxy]).to be_nil
    end
  end

  context 'without a bound port' do
    let(:dashboard_service) do
      { 'image' => 'ghcr.io/solectrus/solectrus:latest', 'ports' => ['3000:3000'] }
    end

    it 'does not set bind_ip' do
      expect(importer.result[:reverse_proxy]).to be_nil
    end
  end
end
