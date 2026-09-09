RSpec.describe ConnectionTesting do
  describe '.loopback_host?' do
    ['localhost', 'LocalHost', ' 127.0.0.1 ', '127.1.2.3', '::1', '[::1]', '0.0.0.0'].each do |host|
      it "recognizes #{host.inspect}" do
        expect(described_class).to be_loopback_host(host)
      end
    end

    ['192.168.178.43', 'raspberrypi.fritz.box', '', nil].each do |host|
      it "passes #{host.inspect}, which can reach the network" do
        expect(described_class).not_to be_loopback_host(host)
      end
    end
  end

  describe '.run' do
    it 'reports an error for an unknown target' do
      expect(described_class.run(target: 'nope', check: 'reachability', values: {}))
        .to have_attributes(ok: false, reason: :error)
    end
  end
end
