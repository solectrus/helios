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

  # HELIOS bakes the bind IP into the ports it emits itself, so the variable is
  # dead weight once every reader is managed. A service HELIOS does not emit
  # keeps its ports verbatim, `${HELIOS_BIND_IP}` and all — dropping the
  # variable would leave that reference resolving to nothing, and the service
  # would publish on every interface instead of the private one.
  describe 'the HELIOS_BIND_IP variable itself' do
    subject(:env_vars) { importer.result[:unmanaged]&.dig('env_vars') || {} }

    let(:dashboard_service) do
      { 'image' => 'ghcr.io/solectrus/solectrus:latest', 'ports' => ['192.168.178.20:3000:3000'] }
    end
    let(:stack_reader) do
      instance_double(
        Import::StackReader,
        raw_env: { 'HELIOS_BIND_IP' => '192.168.178.20' },
        raw_compose: raw_compose,
        services: services,
        stack_dir: '/srv/solectrus',
      ).tap { |double| allow(double).to receive(:service) { |name| services[name] } }
    end
    # What `docker compose config` resolved the references to is what `services`
    # carries; the raw compose keeps the text the file was written with.
    let(:raw_compose) do
      {
        'services' =>
          services.transform_values do |config|
            config.merge('ports' => config['ports'].map { |p| p.sub('192.168.178.20', '${HELIOS_BIND_IP}') })
          end,
      }
    end

    context 'when only managed services publish a bound port' do
      it 'drops the variable' do
        expect(env_vars).not_to have_key('HELIOS_BIND_IP')
      end
    end

    context 'when an unmanaged service publishes a bound port' do
      let(:services) do
        super().merge('grafana' => { 'image' => 'grafana/grafana', 'ports' => ['192.168.178.20:3001:3000'] })
      end

      it 'keeps the variable so the preserved port still resolves' do
        expect(env_vars).to include('HELIOS_BIND_IP' => '192.168.178.20')
      end

      it 'still captures the bind IP for the managed services' do
        expect(importer.result[:reverse_proxy]).to include('bind_ip' => '192.168.178.20')
      end
    end
  end

  # Router labels without a Traefik of the stack's own name an external one: it
  # reads them over a Docker network the two stacks share. real_world/user5
  # runs that way, and its labels sit under `deploy` because the stack was
  # written for Swarm.
  describe 'an external Traefik that reads the labels of this stack' do
    let(:rule) { { 'traefik.http.routers.solectrus.rule' => 'Host(`solar.example.com`)' } }

    context 'with the labels on the service' do
      let(:dashboard_service) do
        { 'image' => 'ghcr.io/solectrus/solectrus:latest', 'labels' => rule }
      end

      it 'names the external mode' do
        expect(importer.result[:reverse_proxy]).to eq('mode' => 'external')
      end

      it 'stores the routed host as the address of the installation' do
        expect(importer.result[:system]).to include('app_host' => 'solar.example.com')
      end
    end

    context 'with the labels under deploy' do
      let(:dashboard_service) do
        { 'image' => 'ghcr.io/solectrus/solectrus:latest', 'deploy' => { 'labels' => rule } }
      end

      it 'names the external mode' do
        expect(importer.result[:reverse_proxy]).to eq('mode' => 'external')
      end
    end

    # A Traefik HELIOS takes over carries settings of its own. An external one
    # is configured where it runs, so nothing but the mode is recovered.
    context 'with a Traefik of the stack own' do
      let(:services) do
        { 'dashboard' => dashboard_service, 'traefik' => { 'image' => 'traefik:v3.7' } }
      end
      let(:dashboard_service) do
        { 'image' => 'ghcr.io/solectrus/solectrus:latest', 'labels' => rule }
      end

      it 'names the managed mode and keeps the Traefik image' do
        expect(importer.result[:reverse_proxy])
          .to include('mode' => 'internal', 'image' => 'traefik:v3.7')
      end
    end
  end
end
