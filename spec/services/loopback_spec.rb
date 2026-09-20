RSpec.describe Loopback do
  # The second group carries the brackets and the space that #host? strips
  # before it judges, and that the field passes on as typed.
  let(:loopback) do
    %w[localhost LOCALHOST helios.localhost 127.0.0.1 127.1.2.3 ::1 0.0.0.0] +
      ['[::1]', '[localhost]', '  localhost  ', " 127.0.0.1\t"]
  end
  let(:routable) do
    %w[solectrus.fritz.box 192.168.1.10 example.com mylocalhost 10.0.0.5 x.localhost.example.com] +
      ['  example.com  ']
  end

  describe '.host?' do
    it 'knows an address that reaches only whoever asks' do
      expect(loopback).to all(satisfy { |host| described_class.host?(host) })
    end

    it 'passes an address that names the machine to others' do
      expect(routable).to all(satisfy { |host| !described_class.host?(host) })
    end

    it 'passes a blank address, which names nothing at all' do
      expect(described_class.host?(nil)).to be false
      expect(described_class.host?(' ')).to be false
    end
  end

  # The pattern travels to the browser, where the same addresses have to fail.
  describe 'SURVEY_PATTERN' do
    subject(:pattern) { Regexp.new(described_class::SURVEY_PATTERN, Regexp::IGNORECASE) }

    it 'refuses every address .host? knows' do
      expect(loopback).to all(satisfy { |host| !host.match?(pattern) })
    end

    it 'takes every address .host? passes' do
      expect(routable).to all(match(pattern))
    end
  end
end
