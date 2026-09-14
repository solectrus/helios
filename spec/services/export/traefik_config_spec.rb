RSpec.describe Export::TraefikConfig do
  subject(:output) { described_class.new(configuration).to_s }

  before { with_config_yaml }

  let(:configuration) do
    config = Configuration.current
    config.update('system', { 'app_host' => 'demo.example.com', 'timezone' => 'Europe/Berlin' })
    config.update('deployment', { 'mode' => 'dashboard_only' })
    config.update('reverse_proxy', { 'mode' => 'external', 'bind_ip' => '10.0.0.5' })
    # The dashboard runs for sensors to be seen (see
    # Configuration#dashboard_required?), and only a service that runs is
    # routed.
    config.update_sensor('house_power', { 'source' => 'external', 'measurement' => 'm', 'field' => 'f' })
    config
  end
  let(:document) { YAML.safe_load(output) }

  it 'routes the dashboard on the bare app_host to the bind IP' do
    expect(document.dig('http', 'routers', 'solectrus-dashboard', 'rule')).to eq('Host(`demo.example.com`)')
    expect(document.dig('http', 'services', 'solectrus-dashboard', 'loadBalancer', 'servers', 0, 'url'))
      .to eq('http://10.0.0.5:3000')
  end

  it 'routes influxdb on a subdomain to its host port' do
    expect(document.dig('http', 'routers', 'solectrus-influxdb', 'rule')).to eq('Host(`influxdb.demo.example.com`)')
    expect(document.dig('http', 'services', 'solectrus-influxdb', 'loadBalancer', 'servers', 0, 'url'))
      .to eq('http://10.0.0.5:8086')
  end

  # The router sends every request for the subdomain to a host port, and an
  # InfluxDB that publishes none refuses the connection. The external Traefik
  # would answer the subdomain with a gateway error instead of not answering it.
  context 'with InfluxDB kept inside the stack' do
    before do
      configuration.update('deployment', { 'mode' => 'full' })
      configuration.update('influxdb', { 'publish_port' => false })
    end

    it 'leaves influxdb out' do
      expect(document.dig('http', 'routers')).not_to have_key('solectrus-influxdb')
      expect(document.dig('http', 'services')).not_to have_key('solectrus-influxdb')
    end

    it 'keeps routing the dashboard' do
      expect(document.dig('http', 'routers', 'solectrus-dashboard', 'rule')).to eq('Host(`demo.example.com`)')
    end
  end

  it 'emits placeholders for the user-specific certResolver and middlewares' do
    router = document.dig('http', 'routers', 'solectrus-dashboard')
    expect(router['tls']['certResolver']).to eq('CHANGE_ME')
    expect(router['middlewares']).to eq(['CHANGE_ME'])
  end

  # A balcony plant turns Ingest on, and the external Traefik has to reach it
  # on its own port.
  context 'with Ingest running' do
    before do
      configuration.update('deployment', { 'mode' => 'full' })
      configuration.update('shelly', { 'connection' => 'local', 'interval' => '5' })
      configuration.update_sensor('inverter_power_2', {
                                    'source' => 'shelly',
                                    'is_balcony' => true,
                                    'shelly_host' => 'shelly-balcony.local',
                                    'measurement' => 'balcony',
                                    'field' => 'power',
                                  })
    end

    it 'routes ingest on a subdomain to port 4567' do
      expect(document.dig('http', 'routers', 'solectrus-ingest', 'rule')).to eq('Host(`ingest.demo.example.com`)')
      expect(document.dig('http', 'services', 'solectrus-ingest', 'loadBalancer', 'servers', 0, 'url'))
        .to eq('http://10.0.0.5:4567')
    end
  end

  it 'starts with an explanatory header comment' do
    expect(output).to start_with('# Traefik dynamic configuration')
  end

  # A placeholder in a host rule looks like a domain, so the header has to name
  # it. It names only the ones the file carries: everything else would send the
  # reader looking for a word that is not there.
  describe 'the placeholder section of the header' do
    it 'explains the placeholder a filled-in configuration leaves behind' do
      expect(output).to include('#   CHANGE_ME  The name of your ACME resolver')
      expect(output).not_to include('YOUR_DOMAIN')
      expect(output).not_to include('HOST_IP')
    end

    context 'without an address and without a bind IP' do
      let(:configuration) do
        config = Configuration.current
        config.update('deployment', { 'mode' => 'dashboard_only' })
        config.update('reverse_proxy', { 'mode' => 'external' })
        # The dashboard runs for sensors to be seen (see
        # Configuration#dashboard_required?), and only a service that runs is
        # routed.
        config.update_sensor('house_power', { 'source' => 'external', 'measurement' => 'm', 'field' => 'f' })
        config
      end

      it 'explains all three, and the host rule carries the domain placeholder' do
        expect(document.dig('http', 'routers', 'solectrus-dashboard', 'rule')).to eq('Host(`YOUR_DOMAIN`)')
        expect(output).to include('#   YOUR_DOMAIN  The domain that leads to this machine.')
        expect(output).to include('#   HOST_IP      The address that Traefik connects to.')
      end
    end
  end
end
