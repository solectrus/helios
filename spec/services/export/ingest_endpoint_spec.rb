RSpec.describe Export::IngestEndpoint do
  subject(:url) { described_class.url(Configuration.current) }

  describe '.url' do
    it 'points at the published host port of the configured host' do
      with_config_yaml('system' => { 'app_host' => 'solectrus.fritz.box' })

      expect(url).to eq('http://solectrus.fritz.box:4567')
    end

    # A URL tells the colons of an IPv6 address from the one in front of the
    # port by the brackets, which the stored address does not carry.
    it 'brackets an IPv6 address in front of the port' do
      with_config_yaml('system' => { 'app_host' => '2001:db8::1' })

      expect(url).to eq('http://[2001:db8::1]:4567')
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

    # The managed Traefik answers the domain of the stack on an entrypoint of
    # its own, so the address keeps the port and gains the TLS in front of it.
    it 'names the entrypoint of the managed Traefik' do
      with_config_yaml(
        'system' => { 'app_host' => 'solectrus.example.com' },
        'reverse_proxy' => { 'mode' => 'internal' },
        'sensors' => { 'inverter_power_2' => { 'source' => 'external', 'is_balcony' => true } },
      )

      expect(url).to eq('https://solectrus.example.com:4567')
    end

    # A Traefik that HELIOS adopted on import keeps its own routing, so Ingest
    # keeps the host port it publishes beside it.
    it 'names the host port behind an adopted Traefik' do
      with_config_yaml(
        'system' => { 'app_host' => 'solectrus.example.com' },
        'reverse_proxy' => { 'mode' => 'internal', 'command' => ['--providers.docker=true'] },
      )

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
