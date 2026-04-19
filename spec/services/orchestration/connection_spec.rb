RSpec.describe Orchestration::Connection do
  describe '.engine_version' do
    before { allow(described_class).to receive(:configure!) }

    it 'returns a Gem::Version when the daemon reports a version' do
      allow(Docker).to receive(:version).and_return('Version' => '25.0.3')

      expect(described_class.engine_version).to eq(Gem::Version.new('25.0.3'))
    end

    it 'returns nil when the daemon is unreachable' do
      allow(Docker).to receive(:version).and_raise(Excon::Error::Socket)

      expect(described_class.engine_version).to be_nil
    end

    it 'returns nil when the daemon response lacks a Version key' do
      allow(Docker).to receive(:version).and_return({})

      expect(described_class.engine_version).to be_nil
    end

    it 'caches the result so Docker is not queried repeatedly' do
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
      allow(Docker).to receive(:version).and_return('Version' => '24.0.2')

      2.times { described_class.engine_version }

      expect(Docker).to have_received(:version).once
    end
  end
end
