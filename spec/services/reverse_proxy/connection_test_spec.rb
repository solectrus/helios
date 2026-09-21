RSpec.describe ReverseProxy::ConnectionTest do
  subject(:result) { described_class.new.call(check: 'domain', values:) }

  let(:values) { { 'app_host' => 'solectrus.example.com' } }

  before { with_config_yaml }

  # The probe resolves the name itself, so every example says what the name
  # resolves to instead of reaching the network.
  def resolving(host, *addresses)
    allow(Addrinfo).to receive(:getaddrinfo).with(host, nil, nil, :STREAM).and_return(
      addresses.map { |address| instance_double(Addrinfo, ip_address: address) },
    )
  end

  def unresolvable(host)
    allow(Addrinfo).to receive(:getaddrinfo).with(host, nil, nil, :STREAM).and_raise(SocketError)
  end

  # The round trip asks the domain for HELIOS's health endpoint. `boot_id` is
  # what the answer carries; nil stands for a port nothing answers on.
  def answering(boot_id)
    response = instance_double(Net::HTTPResponse)
    allow(response).to receive(:[]).with('x-boot-id').and_return(boot_id)
    http = instance_double(Net::HTTP)
    allow(http).to receive(:request).and_return(response)
    allow(ConnectionTesting::Http).to receive(:start) { |**_args, &block| block.call(http) }
  end

  it 'refuses a check it does not know' do
    expect(described_class.new.call(check: 'nonsense', values:)).to have_attributes(ok: false, reason: :error)
  end

  it 'asks for the address before anything else' do
    expect(described_class.new.call(check: 'domain', values: { 'app_host' => '' }))
      .to have_attributes(ok: false, reason: :incomplete)
  end

  # A name nothing resolves is answered for certain, so it is a failure and not
  # a note like the two answers the probe cannot settle.
  it 'names a domain nothing resolves' do
    unresolvable('solectrus.example.com')

    expect(result).to have_attributes(ok: false, reason: :domain_unresolved, state: 'error',
                                      args: { host: 'solectrus.example.com' })
  end

  it 'reports a probe that fails on its own' do
    allow(Addrinfo).to receive(:getaddrinfo).and_raise(RuntimeError, 'boom')

    expect(result).to have_attributes(ok: false, reason: :error)
  end

  describe 'while HELIOS publishes its own host port' do
    before { resolving('solectrus.example.com', '203.0.113.10') }

    it 'confirms a domain the round trip comes back from' do
      answering(Rails.application.config.boot_id)

      expect(result).to have_attributes(ok: true, reason: :domain_leads_here)
    end

    it 'names the address when nothing answers there' do
      answering(nil)

      expect(result).to have_attributes(ok: false, reason: :domain_elsewhere, state: 'warn',
                                        args: { address: '203.0.113.10' })
    end

    it 'names the address when another HELIOS answers there' do
      answering('some-other-boot-id')

      expect(result).to have_attributes(ok: false, reason: :domain_elsewhere,
                                        args: { address: '203.0.113.10' })
    end

    it 'treats a port that refuses the connection as no answer' do
      allow(ConnectionTesting::Http).to receive(:start).and_raise(Errno::ECONNREFUSED)

      expect(result).to have_attributes(ok: false, reason: :domain_elsewhere)
    end
  end

  # Behind the managed Traefik the port carries a host rule for the domain
  # configured now, so the round trip cannot reach HELIOS under any other name.
  # The addresses of the two names answer the same question instead.
  describe 'behind the built-in Traefik' do
    before do
      with_config_yaml(
        'system' => { 'app_host' => 'old.example.com' },
        'reverse_proxy' => { 'mode' => 'internal' },
      )
    end

    it 'confirms a domain that leads to the same address as the current one' do
      resolving('solectrus.example.com', '203.0.113.10')
      resolving('old.example.com', '203.0.113.10')

      expect(result).to have_attributes(ok: true, reason: :domain_same_server,
                                        args: { current: 'old.example.com' })
    end

    it 'names the address when the two lead apart' do
      resolving('solectrus.example.com', '203.0.113.10')
      resolving('old.example.com', '198.51.100.7')

      expect(result).to have_attributes(ok: false, reason: :domain_elsewhere,
                                        args: { address: '203.0.113.10' })
    end

    it 'says so when the domain is the one already configured' do
      resolving('old.example.com', '203.0.113.10')

      expect(described_class.new.call(check: 'domain', values: { 'app_host' => 'old.example.com' }))
        .to have_attributes(ok: false, reason: :domain_unverified, state: 'warn',
                            args: { address: '203.0.113.10' })
    end
  end

  # An address arrives as the user pasted it, so the probe normalizes it the
  # same way the field does before it asks anything.
  it 'reads a pasted address as a host' do
    resolving('solectrus.example.com', '203.0.113.10')
    answering(Rails.application.config.boot_id)

    expect(described_class.new.call(check: 'domain', values: { 'app_host' => 'https://solectrus.example.com/foo' }))
      .to have_attributes(ok: true, reason: :domain_leads_here)
  end
end
