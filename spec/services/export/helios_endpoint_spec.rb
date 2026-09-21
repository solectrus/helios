RSpec.describe Export::HeliosEndpoint do
  subject(:url) { described_class.url(Configuration.current) }

  describe '.url' do
    it 'points at the published host port of the configured address' do
      with_config_yaml('system' => { 'app_host' => 'solectrus.fritz.box' })

      expect(url).to eq('http://solectrus.fritz.box:3999')
    end

    # A URL tells the colons of an IPv6 address from the one in front of the
    # port by the brackets, which the stored address does not carry.
    it 'brackets an IPv6 address in front of the port' do
      with_config_yaml('system' => { 'app_host' => '2001:db8::1' })

      expect(url).to eq('http://[2001:db8::1]:3999')
    end

    # The built-in Traefik terminates TLS on the :3999 entrypoint, so the port
    # stays and the scheme changes.
    it 'uses HTTPS behind the built-in Traefik' do
      with_config_yaml(
        'system' => { 'app_host' => 'solectrus.example.com' },
        'reverse_proxy' => { 'mode' => 'internal' },
      )

      expect(url).to eq('https://solectrus.example.com:3999')
    end

    # An external proxy routes HELIOS on a subdomain, which the generated
    # Traefik file prescribes and the Open button of the service leads to. Both
    # take the address from Export::PublicUrl, so they name the same one.
    it 'uses the subdomain behind an external proxy' do
      with_config_yaml(
        'system' => { 'app_host' => 'solectrus.example.com' },
        'reverse_proxy' => { 'mode' => 'external', 'bind_ip' => '10.0.0.5' },
      )

      expect(url).to eq('https://helios.solectrus.example.com')
      expect(url).to eq(Export::PublicUrl.build(Configuration.current, 'helios', published: true))
    end

    it 'returns nothing while nothing names the machine' do
      with_config_yaml

      expect(url).to be_nil
    end
  end
end
