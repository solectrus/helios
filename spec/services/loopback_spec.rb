RSpec.describe Loopback do
  describe '.host?' do
    ['localhost', 'LocalHost', ' 127.0.0.1 ', '127.1.2.3', '::1', '[::1]', '0.0.0.0',
     'helios.localhost'].each do |host|
      it "recognizes #{host.inspect}" do
        expect(described_class).to be_host(host)
      end
    end

    ['192.168.178.43', 'raspberrypi.fritz.box', 'localhost.example.com', '', nil].each do |host|
      it "passes #{host.inspect}, which can reach the network" do
        expect(described_class).not_to be_host(host)
      end
    end
  end
end
