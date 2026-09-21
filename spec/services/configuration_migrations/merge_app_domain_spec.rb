RSpec.describe ConfigurationMigrations::MergeAppDomain do
  subject(:up) { described_class.new.up(data) }

  context 'with a managed Traefik' do
    let(:data) do
      {
        'system' => { 'app_host' => '192.168.1.5', 'timezone' => 'Europe/Berlin' },
        'reverse_proxy' => { 'app_domain' => 'solar.example.com', 'image' => 'traefik:v3.7' },
      }
    end

    # The domain is the address the stack answers on. app_host was filled from
    # the browser at the first start and holds the address of the machine on
    # the local network, so the domain wins.
    it 'moves the domain onto the address of the installation' do
      expect(up['system']).to eq('app_host' => 'solar.example.com', 'timezone' => 'Europe/Berlin')
    end

    it 'leaves the reverse proxy section with its own keys alone' do
      expect(up['reverse_proxy']).to eq('mode' => 'internal', 'image' => 'traefik:v3.7')
    end
  end

  # The domain lands on the field every other write path normalizes, so it has
  # to arrive in the same shape: the host alone.
  {
    'https://solar.example.com/' => 'solar.example.com',
    'solar.example.com:3000' => 'solar.example.com',
    '  Solar.Example.COM  ' => 'solar.example.com',
  }.each do |stored, host|
    context "with the stored domain #{stored.inspect}" do
      let(:data) { { 'reverse_proxy' => { 'app_domain' => stored } } }

      it "stores #{host.inspect}" do
        expect(up['system']).to eq('app_host' => host)
      end
    end
  end

  # Such a domain names the machine to itself alone. The form refuses it, so
  # storing it would leave the section unsaveable until it is cleared by hand.
  context 'with a domain that reaches only whoever asks' do
    let(:data) do
      {
        'system' => { 'app_host' => '192.168.1.5' },
        'reverse_proxy' => { 'app_domain' => 'helios.localhost' },
      }
    end

    it 'keeps the address already stored' do
      expect(up['system']).to eq('app_host' => '192.168.1.5')
    end

    it 'still names the managed mode' do
      expect(up['reverse_proxy']).to eq('mode' => 'internal')
    end
  end

  # Such a domain names the machine to itself alone, and nothing else names it
  # either. Traefik routes by host rule, so a rule with nothing in it matches
  # nothing: the stack keeps no mode it cannot run, and the form offers the
  # address of the machine again (see Configuration#adopt_request_host!).
  context 'with a domain that reaches only whoever asks and no address beside it' do
    let(:data) { { 'reverse_proxy' => { 'app_domain' => 'helios.localhost' } } }

    it 'names no mode' do
      expect(up['reverse_proxy']).to eq({})
    end

    it 'stores no address' do
      expect(up['system']).to be_nil
    end
  end

  context 'with a managed Traefik that already names its mode' do
    let(:data) do
      { 'reverse_proxy' => { 'mode' => 'internal', 'app_domain' => 'solar.example.com' } }
    end

    it 'creates the system section for the address' do
      expect(up['system']).to eq('app_host' => 'solar.example.com')
    end
  end

  # The mode was derived from a bind_ip wherever the stack predates the stored
  # field. That derivation goes, so the marker is written out.
  context 'with an external proxy and no stored mode' do
    let(:data) { { 'reverse_proxy' => { 'bind_ip' => '10.0.0.5' } } }

    it 'names the external mode' do
      expect(up['reverse_proxy']).to eq('mode' => 'external', 'bind_ip' => '10.0.0.5')
    end
  end

  context 'with an external proxy that already names its mode' do
    let(:data) { { 'reverse_proxy' => { 'mode' => 'external' } } }

    it 'leaves it alone' do
      expect(up['reverse_proxy']).to eq('mode' => 'external')
    end
  end

  # A section that names neither runs no proxy at all.
  context 'with a section that carries only a certificate address' do
    let(:data) { { 'reverse_proxy' => { 'letsencrypt_email' => 'me@example.com' } } }

    it 'names no mode' do
      expect(up['reverse_proxy']).to eq('letsencrypt_email' => 'me@example.com')
    end
  end

  # An nginx or an Apache in front of the stack leaves one mark in the
  # configuration: the HTTPS flag. The form shows the flag in the external mode
  # alone, so a stack that keeps no mode here loses it on the first save, and
  # the login behind the proxy fails from then on.
  context 'with the HTTPS flag and nothing else naming a proxy' do
    let(:data) { { 'dashboard' => { 'force_ssl' => true } } }

    it 'names the external mode' do
      expect(up['reverse_proxy']).to eq('mode' => 'external')
    end

    it 'leaves the flag where it is stored' do
      expect(up['dashboard']).to eq('force_ssl' => true)
    end
  end

  context 'with the HTTPS flag stored as a word' do
    let(:data) { { 'dashboard' => { 'force_ssl' => 'true' } } }

    it 'names the external mode' do
      expect(up['reverse_proxy']).to eq('mode' => 'external')
    end
  end

  context 'with the HTTPS flag turned off' do
    let(:data) { { 'dashboard' => { 'force_ssl' => false } } }

    it 'names no mode' do
      expect(up).to eq('dashboard' => { 'force_ssl' => false })
    end
  end

  # The managed Traefik terminates TLS itself, so it carries the flag without
  # it being stored. The domain names the mode, and the flag says nothing here.
  context 'with the HTTPS flag beside a managed Traefik' do
    let(:data) do
      {
        'dashboard' => { 'force_ssl' => true },
        'reverse_proxy' => { 'app_domain' => 'solar.example.com' },
      }
    end

    it 'names the managed mode' do
      expect(up['reverse_proxy']).to eq('mode' => 'internal')
    end
  end

  # A migration must never keep the app from booting, so an unexpected shape
  # passes through untouched.
  context 'without a reverse proxy section' do
    let(:data) { { 'deployment' => { 'mode' => 'full' } } }

    it 'passes the data through' do
      expect(up).to eq('deployment' => { 'mode' => 'full' })
    end
  end

  context 'with a section that is not one' do
    let(:data) { { 'reverse_proxy' => 'nonsense' } }

    it 'passes the data through' do
      expect(up).to eq('reverse_proxy' => 'nonsense')
    end
  end
end
