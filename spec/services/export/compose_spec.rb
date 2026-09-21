RSpec.describe Export::Compose do
  subject(:yaml) { described_class.new(Configuration.current).to_yaml }

  # An unmanaged collector adopted from a legacy stack that passed the InfluxDB
  # target through .env via bare `- INFLUX_HOST` entries (older SOLECTRUS compose
  # style). HELIOS suppresses INFLUX_HOST/PORT/SCHEMA from .env on a local stack,
  # so these bare entries would otherwise resolve to nothing at runtime.
  let(:unmanaged) do
    {
      '_unmanaged' => {
        'services' => {
          'tibber-collector' => {
            'image' => 'ghcr.io/solectrus/tibber-collector:latest',
            'environment' => [
              'TZ',
              'INFLUX_HOST',
              'INFLUX_PORT',
              'INFLUX_SCHEMA',
              'INFLUX_ORG',
              'INFLUX_TOKEN=${INFLUX_TOKEN_WRITE}',
              'TIBBER_TOKEN',
            ],
          },
        },
      },
    }
  end

  context 'with a local InfluxDB stack' do
    before { with_config_yaml(unmanaged) }

    it 'bakes the local InfluxDB host/port/schema into the unmanaged service' do
      expect(yaml).to include('- INFLUX_HOST=influxdb')
      expect(yaml).to include('- INFLUX_PORT=8086')
      expect(yaml).to include('- INFLUX_SCHEMA=http')
    end

    it 'leaves other passthroughs bare (still resolved from .env)' do
      expect(yaml).to match(/^\s*- INFLUX_ORG$/)
      expect(yaml).to match(/^\s*- TIBBER_TOKEN$/)
    end

    it 'leaves no bare INFLUX_HOST that would raise KeyError at container start' do
      expect(yaml).not_to match(/^\s*- INFLUX_HOST$/)
      expect(yaml).not_to match(/^\s*- INFLUX_PORT$/)
      expect(yaml).not_to match(/^\s*- INFLUX_SCHEMA$/)
    end
  end

  context 'when in collectors_only mode (external InfluxDB supplied via .env)' do
    before { with_config_yaml(unmanaged.deep_merge('deployment' => { 'mode' => 'collectors_only' })) }

    it 'keeps the passthrough bare so it reads the external target from .env' do
      expect(yaml).to match(/^\s*- INFLUX_HOST$/)
      expect(yaml).not_to include('- INFLUX_HOST=influxdb')
    end
  end

  # A stale passthrough of a service that has since become managed. compose has
  # one entry per service name, so without the guard whichever is written last
  # would decide — and unmanaged services are written last in full mode.
  context 'when a managed service of the same name is configured' do
    before { with_config_yaml(unmanaged.merge('tibber' => { 'token' => 'from-the-survey' })) }

    it 'emits the service exactly once' do
      expect(yaml.scan(/^ {2}tibber-collector:/).size).to eq(1)
    end

    it 'lets the managed service win over the stale passthrough' do
      expect(yaml).to match(/^\s*- INFLUX_MEASUREMENT=\$\{INFLUX_MEASUREMENT_PRICES\}$/)
      expect(yaml).not_to include('Unmanaged service (preserved from existing installation)')
    end
  end

  # The second way an external reverse proxy reaches the stack: it is on a Docker
  # network the two stacks share, finds every service there by name, and the stack
  # publishes no host port at all.
  describe 'on a shared Docker network' do
    subject(:compose) { YAML.safe_load(described_class.new(Configuration.current).to_yaml) }

    let(:proxy) { { 'mode' => 'external', 'proxy_network' => 'edge' } }
    let(:data) do
      {
        'system' => { 'app_host' => 'solar.example.com' },
        'reverse_proxy' => proxy,
        'influxdb' => { 'publish_port' => true },
        'sensors' => { 'inverter_power_2' => { 'source' => 'external', 'is_balcony' => true } },
      }
    end

    before { with_config_yaml(data) }

    def service(name) = compose.dig('services', name)

    it 'declares the network as one another stack owns' do
      expect(compose['networks']).to include('edge' => { 'external' => true })
    end

    it 'keeps the own network of the stack' do
      expect(compose.dig('networks', 'default', 'name')).to eq('solectrus_default')
    end

    # A service that names a network joins that one alone, so a routed service has
    # to name both: the stack's own, and the proxy's.
    it 'puts every routed service on both networks' do
      %w[dashboard influxdb ingest helios].each do |name|
        expect(service(name)['networks']).to eq(%w[default edge]), "#{name} joins the wrong networks"
      end
    end

    it 'keeps the database and the collectors off the shared network' do
      expect(service('postgresql')).not_to have_key('networks')
      expect(service('redis')).not_to have_key('networks')
    end

    it 'publishes no host port for a routed service' do
      %w[dashboard influxdb ingest helios].each do |name|
        expect(service(name)).not_to have_key('ports'), "#{name} still publishes a port"
      end
    end

    # An InfluxDB the user keeps inside the stack is not routed: the proxy answers
    # the internet, and a router would open a database that was left closed.
    context 'with an InfluxDB that is not exposed' do
      let(:data) { super().except('influxdb') }

      it 'leaves it off the shared network and off the host' do
        expect(service('influxdb')).not_to have_key('networks')
        expect(service('influxdb')).not_to have_key('ports')
      end
    end

    context 'with an entrypoint of the proxy named' do
      let(:proxy) { super().merge('proxy_entrypoint' => 'websecure', 'proxy_certresolver' => 'le') }

      it 'routes the dashboard at the address itself' do
        expect(service('dashboard')['labels']).to include(
          'traefik.enable=true',
          'traefik.http.routers.dashboard.rule=Host(`solar.example.com`)',
          'traefik.http.routers.dashboard.entrypoints=websecure',
          'traefik.http.routers.dashboard.tls.certresolver=le',
          'traefik.http.services.dashboard.loadbalancer.server.port=3000',
        )
      end

      it 'routes every other service at a subdomain of it' do
        expect(service('influxdb')['labels'])
          .to include('traefik.http.routers.influxdb.rule=Host(`influxdb.solar.example.com`)')
        expect(service('ingest')['labels'])
          .to include('traefik.http.routers.ingest.rule=Host(`ingest.solar.example.com`)')
        expect(service('helios')['labels'])
          .to include('traefik.http.routers.helios.rule=Host(`helios.solar.example.com`)')
      end

      # A routed service is on two networks and the proxy on one of them. Traefik
      # takes one of the two at random where no label names it, so half of the
      # time it addresses the service where it cannot reach it.
      it 'names the network the proxy reaches every routed service on' do
        %w[dashboard influxdb ingest helios].each do |name|
          expect(service(name)['labels'])
            .to include('traefik.docker.network=edge'), "#{name} names no network"
        end
      end
    end

    context 'with an entrypoint but without a certificate resolver' do
      let(:proxy) { super().merge('proxy_entrypoint' => 'websecure') }

      it 'writes the router without one' do
        expect(service('dashboard')['labels']).to include('traefik.http.routers.dashboard.entrypoints=websecure')
        expect(service('dashboard')['labels'].grep(/certresolver/)).to be_empty
      end
    end

    # An nginx or a Caddy reads no labels: it carries its own routes and finds
    # the service by name on the shared network.
    context 'without an entrypoint' do
      it 'writes no router at all' do
        expect(service('dashboard')['labels']).to eq(['com.centurylinklabs.watchtower.scope=solectrus'])
      end
    end

    # A network the stack was adopted on rather than routed over: no proxy claims
    # it, so every service joins it and the published ports stay.
    context 'without a reverse proxy' do
      let(:proxy) { { 'proxy_network' => 'edge' } }

      it 'puts every service on it' do
        expect(service('postgresql')['networks']).to eq(%w[default edge])
        expect(service('dashboard')['networks']).to eq(%w[default edge])
      end

      it 'keeps the published ports' do
        expect(service('dashboard')['ports']).to eq(['3000:3000'])
      end
    end
  end
end
