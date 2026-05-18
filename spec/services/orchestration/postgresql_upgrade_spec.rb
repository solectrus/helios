RSpec.describe Orchestration::PostgresqlUpgrade do
  describe '.target_major' do
    it 'is the major version of the recommended PostgreSQL image' do
      expect(described_class.target_major).to eq(18)
    end
  end

  describe '.current_major' do
    it 'reads the major version from the container' do
      container = instance_double(Orchestration::Container, version: '17.5')
      expect(described_class.current_major(container)).to eq(17)
    end

    it 'is nil without a container' do
      expect(described_class.current_major(nil)).to be_nil
    end
  end

  describe '.available?' do
    subject(:available?) { described_class.available?(container) }

    def container_double(running:, version:)
      instance_double(Orchestration::Container, running?: running, version:)
    end

    context 'when an older major is running' do
      let(:container) { container_double(running: true, version: '17.5') }

      it { is_expected.to be true }
    end

    context 'when already on the target major' do
      let(:container) { container_double(running: true, version: '18.1') }

      it { is_expected.to be false }
    end

    context 'when PostgreSQL is not running' do
      let(:container) { container_double(running: false, version: '17.5') }

      it { is_expected.to be false }
    end

    context 'without a container' do
      let(:container) { nil }

      it { is_expected.to be false }
    end
  end
end
