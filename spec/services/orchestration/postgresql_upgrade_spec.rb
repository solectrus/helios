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

  # finish! runs after the database is already upgraded and verified. It
  # reconciles the running services against the rewritten compose — recreating
  # drifted dependents (the dashboard's DB_HOST) and pruning the pre-upgrade
  # orphan — rather than only re-baselining postgresql. The real reconcile and
  # orphan pruning are exercised against Docker in the integration spec; here
  # we pin the wiring and the failure handling.
  describe '#finish! (stack reconcile)' do
    subject(:finish!) { described_class.new.send(:finish!) }

    let(:services) { instance_double(Compose::ServiceCollection, names: %w[postgresql dashboard]) }
    let(:compose) { instance_double(Compose::File, services:) }

    def running(service_name)
      instance_double(Orchestration::Container, running?: true, service_name:)
    end

    before do
      allow(FileUtils).to receive(:rm_f)
      allow(Compose).to receive(:load).and_return(compose)
      allow(Orchestration::Container).to receive(:all).and_return(
        [running('dashboard'), running('postgresql')],
      )
      allow(Orchestration::AffectedServices).to receive(:update_deployed_hash!)
    end

    it 'reconciles the running compose services and baselines each as deployed' do
      allow(Orchestration::Runner).to receive(:reconcile)

      finish!

      expect(Orchestration::Runner).to have_received(:reconcile).with(
        a_collection_containing_exactly('dashboard', 'postgresql'),
      )
      expect(Orchestration::AffectedServices).to have_received(:update_deployed_hash!).with('dashboard')
      expect(Orchestration::AffectedServices).to have_received(:update_deployed_hash!).with('postgresql')
    end

    it 'reports a reconcile failure without rolling back' do
      allow(Orchestration::Runner).to receive(:reconcile).and_raise(
        Orchestration::Runner::CommandError.new('reconcile', stdout: 'network unreachable'),
      )

      expect { finish! }.to raise_error(
        described_class::UpgradeError, /stop all services|Dienste stoppen/
      )
    end
  end
end
