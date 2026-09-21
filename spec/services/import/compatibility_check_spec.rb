RSpec.describe Import::CompatibilityCheck do
  # Builds a check from the donor stack of a real import scenario.
  def check_for(scenario)
    base = Rails.root.join('spec/scenarios/import', scenario, 'input')
    compose = Compose::FILENAMES.lazy.map { |f| base.join(f) }.find(&:file?)
    reader = Import::StackReader.new(compose_path: compose, env_path: base.join('.env'))
    described_class.new(reader)
  end

  describe '#unsupported_services' do
    it 'accepts a pure SOLECTRUS stack' do
      expect(check_for('with_custom_traefik').unsupported_services).to be_empty
    end

    it 'accepts dozzle as an allowlisted companion' do
      expect(check_for('real_world/user3').unsupported_services).to be_empty
    end

    it 'accepts senec-charger (SOLECTRUS, fully managed)' do
      expect(check_for('with_senec_charger').unsupported_services).to be_empty
    end

    it 'accepts tibber-collector (SOLECTRUS, fully managed)' do
      expect(check_for('with_tibber').unsupported_services).to be_empty
    end

    it 'flags a self-hosted mosquitto broker (user2)' do
      names = check_for('real_world/user2').unsupported_services.pluck('service')
      expect(names).to contain_exactly('mosquitto')
    end

    it 'flags foreign services while keeping dozzle (user6)' do
      names = check_for('real_world/user6').unsupported_services.pluck('service')
      expect(names).to contain_exactly('mosquitto', 'pgadmin')
    end

    it 'flags an unknown third-party image' do
      expect(check_for('with_unknown').unsupported_services)
        .to contain_exactly('service' => 'nginx', 'image' => 'nginx:alpine')
    end
  end

  # HELIOS writes the stack's own network and the single external one an
  # outside proxy reaches it over. A second one would be dropped, and the
  # services on it would lose the way they are reached today.
  describe '#unsupported_networks' do
    def check_for_compose(compose)
      reader = instance_double(Import::StackReader, raw_compose: compose)
      described_class.new(reader)
    end

    it 'accepts a stack on its own network alone' do
      expect(check_for_compose({ 'services' => { 'dashboard' => {} } }).unsupported_networks).to be_empty
    end

    it 'accepts the one external network a proxy reaches the stack over' do
      compose = {
        'services' => { 'dashboard' => { 'networks' => %w[default edge] } },
        'networks' => { 'edge' => { 'external' => true } },
      }

      expect(check_for_compose(compose).unsupported_networks).to be_empty
    end

    it 'flags a second external network' do
      compose = {
        'services' => { 'dashboard' => { 'networks' => %w[edge backend] } },
        'networks' => { 'edge' => { 'external' => true }, 'backend' => { 'external' => true } },
      }

      expect(check_for_compose(compose).unsupported_networks).to contain_exactly('backend')
    end

    it 'flags a network the stack declares itself' do
      compose = {
        'services' => { 'dashboard' => { 'networks' => %w[backend] } },
        'networks' => { 'backend' => {} },
      }

      expect(check_for_compose(compose).unsupported_networks).to contain_exactly('backend')
    end

    it 'raises with the network it cannot write again' do
      compose = {
        'services' => { 'dashboard' => { 'image' => 'ghcr.io/solectrus/solectrus:latest',
                                         'networks' => %w[backend] } },
        'networks' => { 'backend' => {} },
      }
      reader = instance_double(Import::StackReader, raw_compose: compose)
      allow(reader).to receive(:service).and_return(nil)
      allow(reader).to receive(:service).with('dashboard').and_return(compose.dig('services', 'dashboard'))

      expect { described_class.new(reader).call! }
        .to raise_error(Import::UnsupportedStackError) { |error| expect(error.networks).to eq(['backend']) }
    end
  end

  # HELIOS writes the routers of its own services, so a label that says
  # something else would be replaced by its own on the next export.
  describe '#unsupported_routing' do
    def check_for_labels(labels, service: 'dashboard')
      compose = { 'services' => { service => { 'labels' => labels } } }
      reader = instance_double(Import::StackReader, raw_compose: compose)
      allow(reader).to receive(:service).and_return(nil)
      allow(reader).to receive(:service).with(service).and_return(compose.dig('services', service))
      described_class.new(reader)
    end

    it 'accepts the labels HELIOS writes itself' do
      labels = [
        'traefik.enable=true',
        'traefik.http.routers.app-solectrus.rule=Host(`solectrus.example.com`)',
        'traefik.http.routers.app-solectrus.entrypoints=websecure',
        'traefik.http.routers.app-solectrus.tls.certresolver=myresolver',
        'traefik.http.services.app-solectrus.loadbalancer.server.port=3000',
      ]

      expect(check_for_labels(labels).unsupported_routing).to be_empty
    end

    # A stack an outside proxy routes over a shared network carries it, and
    # HELIOS writes it again (see Export::Services::Base#network_label).
    it 'accepts the network a routed service names' do
      labels = [
        'traefik.enable=true',
        'traefik.http.routers.dashboard.rule=Host(`solectrus.example.com`)',
        'traefik.docker.network=edge',
      ]

      expect(check_for_labels(labels).unsupported_routing).to be_empty
    end

    # The shape of the older SOLECTRUS setup: port 80 answers through a
    # middleware. HELIOS does the same on the `web` entrypoint.
    it 'accepts a router that only sends a request on to HTTPS' do
      labels = [
        'traefik.http.routers.app.rule=Host(`solectrus.example.com`)',
        'traefik.http.middlewares.redirect-to-https.redirectscheme.scheme=https',
        'traefik.http.routers.redirs.rule=hostregexp(`{host:.+}`)',
        'traefik.http.routers.redirs.middlewares=redirect-to-https',
      ]

      expect(check_for_labels(labels).unsupported_routing).to be_empty
    end

    it 'flags a middleware HELIOS does not know' do
      labels = ['traefik.http.middlewares.test-ratelimit.ratelimit.average=100']

      expect(check_for_labels(labels).unsupported_routing)
        .to contain_exactly('service' => 'dashboard',
                            'label' => 'traefik.http.middlewares.test-ratelimit.ratelimit.average=100')
    end

    it 'flags a router that answers at another address' do
      labels = [
        'traefik.http.routers.app.rule=Host(`solectrus.example.com`)',
        'traefik.http.routers.db.rule=Host(`influx.example.com`)',
      ]

      expect(check_for_labels(labels).unsupported_routing.pluck('label'))
        .to contain_exactly('traefik.http.routers.db.rule=Host(`influx.example.com`)')
    end

    it 'raises with the label it cannot write again' do
      labels = ['traefik.http.middlewares.auth.basicauth.users=admin:hash']
      check = check_for_labels(labels)

      expect { check.call! }
        .to raise_error(Import::UnsupportedStackError) { |error| expect(error.routing.pluck('label')).to eq(labels) }
    end
  end

  describe '#call!' do
    it 'passes for a supported stack' do
      expect { check_for('real_world/user3').call! }.not_to raise_error
    end

    it 'raises UnsupportedStackError naming the offending services' do
      expect { check_for('real_world/user6').call! }
        .to raise_error(Import::UnsupportedStackError) do |error|
          expect(error.services.map { |s| s['service'] })
            .to contain_exactly('mosquitto', 'pgadmin')
        end
    end
  end
end
