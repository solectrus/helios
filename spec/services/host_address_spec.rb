RSpec.describe HostAddress do
  # One table behind every example below: the value as a user hands it over,
  # the host it leaves behind, and whether that host reaches only whoever asks.
  #
  # SURVEY_PATTERN is held to the same table, because the browser judges a
  # typed address first and the server judges it again. The two used to be
  # written out separately and answered differently.
  let(:cases) do
    [
      # [typed, host, reaches only whoever asks]

      # The shapes a browser hands over
      ['solectrus.fritz.box', 'solectrus.fritz.box', false],
      ['  Solectrus.Fritz.Box  ', 'solectrus.fritz.box', false],
      ['http://solectrus.fritz.box/', 'solectrus.fritz.box', false],
      ['https://solectrus.fritz.box:3000/services', 'solectrus.fritz.box', false],
      ['nas.fritz.box/services', 'nas.fritz.box', false],
      ['192.168.1.10', '192.168.1.10', false],
      ['192.168.1.10:8086', '192.168.1.10', false],

      # An IPv6 address keeps the colons of its own, in brackets or without
      ['2001:db8::1', '2001:db8::1', false],
      ['[2001:db8::1]', '2001:db8::1', false],
      ['[2001:db8::1]:3000', '2001:db8::1', false],

      # A name that only looks like one of the group below
      ['mylocalhost', 'mylocalhost', false],
      ['localhost.example.com', 'localhost.example.com', false],
      ['x.localhost.example.com', 'x.localhost.example.com', false],

      # Reaches only whoever asks
      ['localhost', 'localhost', true],
      ['LOCALHOST', 'localhost', true],
      ['localhost:3000', 'localhost', true],
      ['http://localhost:3000/', 'localhost', true],
      ['http://localhost/services', 'localhost', true],
      ['127.0.0.1/', '127.0.0.1', true],
      ['helios.localhost', 'helios.localhost', true],
      ['helios.localhost:3999', 'helios.localhost', true],
      ['127.0.0.1', '127.0.0.1', true],
      ['127.1.2.3', '127.1.2.3', true],
      [' 127.0.0.1:8086 ', '127.0.0.1', true],
      ['::1', '::1', true],
      ['[::1]', '::1', true],
      ['[::1]:3000', '::1', true],
      ['0.0.0.0', '0.0.0.0', true],
    ]
  end

  # A map rather than an example per address: a failure then names the address
  # that answered differently, and the table above stays the only place a case
  # is written down.
  def answers(&)
    cases.to_h { |typed, host, loopback| [typed, yield(typed, host, loopback)] }
  end

  describe '.normalize' do
    it 'leaves the host alone' do
      expect(answers { |typed, _, _| described_class.normalize(typed) })
        .to eq(answers { |_, host, _| host })
    end

    it 'answers nil where nothing names a host' do
      expect(described_class.normalize(nil)).to be_nil
      expect(described_class.normalize('  ')).to be_nil
      expect(described_class.normalize('https://')).to be_nil
    end
  end

  describe '.loopback?' do
    it 'knows an address that reaches only whoever asks' do
      expect(answers { |typed, _, _| described_class.loopback?(typed) })
        .to eq(answers { |_, _, loopback| loopback })
    end

    it 'passes a blank address, which names nothing at all' do
      expect(described_class.loopback?(nil)).to be false
      expect(described_class.loopback?(' ')).to be false
    end
  end

  describe '.for_url' do
    it 'brackets an address that carries colons of its own' do
      expect(described_class.for_url('2001:db8::1')).to eq('[2001:db8::1]')
    end

    it 'leaves a name or an IPv4 address alone' do
      expect(described_class.for_url('nas.fritz.box')).to eq('nas.fritz.box')
      expect(described_class.for_url('192.168.1.10')).to eq('192.168.1.10')
    end
  end

  # The pattern travels to the browser, where the same addresses have to fail.
  describe 'SURVEY_PATTERN' do
    subject(:pattern) { Regexp.new(described_class::SURVEY_PATTERN, Regexp::IGNORECASE) }

    it 'answers every address the way .loopback? does' do
      expect(answers { |typed, _, _| typed.match?(pattern) })
        .to eq(answers { |_, _, loopback| !loopback })
    end

    # The table above holds the addresses worth reading. This holds every shape
    # they can arrive in. The two rules are written in two languages, and each
    # earlier attempt to keep them equal by hand let one shape through: first
    # the port, then the path. So the shapes are built rather than listed.
    it 'answers every shape of every address the way .loopback? does' do
      hosts = %w[localhost helios.localhost a.b.localhost 127.0.0.1 127.1.2.3 ::1 [::1] 0.0.0.0
                 nas.fritz.box 192.168.1.10 mylocalhost localhost.example.com 2001:db8::1]
      shapes = ['', 'http://', 'https://', 'HTTP://'].product(
        ['', ':3000'], ['', '/', '/services', '/a/b'], ['', '  ']
      )

      disagreed = hosts.product(shapes).filter_map do |host, (scheme, port, path, space)|
        typed = "#{space}#{scheme}#{host}#{port}#{path}#{space}"
        typed unless typed.match?(pattern) == !described_class.loopback?(typed)
      end

      expect(disagreed).to be_empty
    end
  end
end
