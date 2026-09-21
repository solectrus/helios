RSpec.describe Orchestration::ProxyNetwork do
  def with_networks(names)
    allow(Orchestration::DockerCli).to receive(:network_names).and_return(names)
  end

  describe '.missing_name' do
    it 'names a network Docker does not have' do
      with_networks(%w[bridge host])

      expect(described_class.missing_name('edge')).to eq('edge')
    end

    it 'says nothing about one it has' do
      with_networks(%w[bridge edge])

      expect(described_class.missing_name('edge')).to be_nil
    end

    # A name is either there or not, never nearly there: compose asks for the
    # name it was given.
    it 'compares the whole name' do
      with_networks(%w[edge-public])

      expect(described_class.missing_name('edge')).to eq('edge')
    end

    it 'says nothing without a name' do
      with_networks(%w[bridge])

      expect(described_class.missing_name('')).to be_nil
    end

    # A daemon out of reach is not a missing network. Answering otherwise would
    # refuse every network for as long as Docker is quiet.
    it 'says nothing while Docker does not answer' do
      with_networks(nil)

      expect(described_class.missing_name('edge')).to be_nil
    end
  end

  describe '.missing' do
    subject(:missing) { described_class.missing(configuration) }

    let(:configuration) { Configuration.current }

    before { with_networks(%w[bridge]) }

    context 'with a shared network in the configuration' do
      before do
        with_config_yaml('reverse_proxy' => { 'mode' => 'external', 'proxy_network' => 'edge' })
      end

      it { is_expected.to eq('edge') }
    end

    context 'without one' do
      before { with_config_yaml('reverse_proxy' => { 'mode' => 'external' }) }

      it { is_expected.to be_nil }
    end
  end
end
