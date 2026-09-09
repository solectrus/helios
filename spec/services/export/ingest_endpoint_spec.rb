RSpec.describe Export::IngestEndpoint do
  subject(:url) { described_class.url(Configuration.current) }

  describe '.url' do
    it 'points at the published host port of the configured host' do
      with_config_yaml('system' => { 'app_host' => 'solectrus.fritz.box' })

      expect(url).to eq('http://solectrus.fritz.box:4567')
    end

    # An external Traefik routes Ingest on its own subdomain
    # (TraefikConfig::ROUTABLE), so the host port is not the address there.
    it 'uses the Ingest subdomain behind an external Traefik' do
      with_config_yaml(
        'system' => { 'app_host' => 'solectrus.example.com' },
        'reverse_proxy' => { 'mode' => 'external', 'bind_ip' => '192.168.1.10' },
      )

      expect(url).to eq('https://ingest.solectrus.example.com')
    end

    # Managed Traefik routes the dashboard and InfluxDB only, so Ingest keeps
    # its host port and the domain merely names the machine.
    it 'falls back to the proxy domain when no host is configured' do
      with_config_yaml('reverse_proxy' => { 'mode' => 'managed', 'app_domain' => 'solectrus.example.com' })

      expect(url).to eq('http://solectrus.example.com:4567')
    end

    # app_host is required in its own form but in no completeness check, and an
    # imported stack without APP_HOST keeps it empty. A caller then names the
    # port instead of building an address around a placeholder.
    it 'returns nothing while nothing names the machine' do
      with_config_yaml

      expect(url).to be_nil
    end
  end
end
