RSpec.describe Export::OpenEndpoint do
  subject(:endpoint) do
    described_class.resolve(service_name:, public_port:, configuration:)
  end

  let(:configuration) { Configuration.from_data(data) }
  let(:data) { {} }
  let(:public_port) { nil }

  describe 'without a reverse proxy' do
    let(:service_name) { 'dashboard' }

    context 'with a published host port' do
      let(:public_port) { 3000 }

      it { is_expected.to eq(port: 3000) }
    end

    context 'without a published host port' do
      it { is_expected.to be_nil }
    end
  end

  describe 'behind a managed Traefik' do
    let(:data) { { 'reverse_proxy' => { 'app_domain' => 'solectrus.example.com' } } }
    let(:service_name) { 'dashboard' }

    # The managed dashboard is routed at the domain root and publishes no host
    # port, so the absolute URL is preferred over any port.
    it { is_expected.to eq(url: 'https://solectrus.example.com') }

    context 'when a host port is also published' do
      let(:public_port) { 3000 }

      it 'still prefers the proxy URL' do
        expect(endpoint).to eq(url: 'https://solectrus.example.com')
      end
    end
  end

  describe 'Traefik itself' do
    let(:service_name) { 'traefik' }
    let(:public_port) { 443 }

    it 'never has a browsable endpoint' do
      expect(endpoint).to be_nil
    end
  end
end
