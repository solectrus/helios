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
  # reconciles PostgreSQL and the services depending on it against the rewritten
  # compose — recreating drifted dependents (the dashboard's DB_HOST) and pruning
  # the pre-upgrade orphan. The real reconcile and orphan pruning are exercised
  # against Docker in the integration spec; here we pin which services are
  # picked, and the failure handling.
  describe '#finish! (stack reconcile)' do
    subject(:finish!) { described_class.new.send(:finish!) }

    # A real collection, so the depends_on lookup runs against the actual
    # compose structure: the dashboard talks to the database, the forecast
    # collector does not.
    let(:services) do
      Compose::ServiceCollection.new(
        'postgresql' => { 'image' => 'postgres:18-alpine' },
        'dashboard' => { 'depends_on' => { 'postgresql' => { 'condition' => 'service_healthy' } } },
        'forecast-collector' => { 'depends_on' => { 'influxdb' => { 'condition' => 'service_healthy' } } },
      )
    end
    let(:compose) { instance_double(Compose::File, services:) }

    def running(service_name)
      instance_double(Orchestration::Container, running?: true, service_name:)
    end

    before do
      allow(FileUtils).to receive(:rm_f)
      allow(Compose).to receive(:load).and_return(compose)
      allow(Orchestration::Container).to receive(:all).and_return(
        [running('dashboard'), running('postgresql'), running('forecast-collector')],
      )
      allow(Orchestration::AffectedServices).to receive(:update_deployed_hash!)
    end

    it 'reconciles PostgreSQL and its dependents, and baselines each as deployed' do
      allow(Orchestration::Runner).to receive(:reconcile)

      finish!

      expect(Orchestration::Runner).to have_received(:reconcile).with(
        a_collection_containing_exactly('dashboard', 'postgresql'),
      )
      expect(Orchestration::AffectedServices).to have_received(:update_deployed_hash!).with('dashboard')
      expect(Orchestration::AffectedServices).to have_received(:update_deployed_hash!).with('postgresql')
    end

    # Drift unrelated to the upgrade (an imported stack that was never
    # redeployed drifts everywhere) must not be swept along: recreating those
    # containers discards their logs, the only trace left when something fails.
    it 'leaves services that do not depend on PostgreSQL alone' do
      allow(Orchestration::Runner).to receive(:reconcile)

      finish!

      expect(Orchestration::Runner).not_to have_received(:reconcile).with(
        array_including('forecast-collector'),
      )
      expect(Orchestration::AffectedServices).not_to have_received(:update_deployed_hash!)
        .with('forecast-collector')
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

  # The post-restore check counts tables — in SOLECTRUS' own database. Pinned
  # here because getting the name wrong is silent: against the empty `solectrus`
  # that the postgres image creates from POSTGRES_DB, the check compared 0 to 0
  # and passed no matter what the restore did.
  describe '#verify_restore!' do
    let(:upgrade) { described_class.new }

    it 'counts the tables in SOLECTRUS own database' do
      allow(Orchestration::Runner).to receive(:compose_exec).and_return(['3', '', 0])

      expect(upgrade.send(:count_tables)).to eq(3)
      expect(Orchestration::Runner).to have_received(:compose_exec).with(
        'postgresql', 'psql', '-U', 'postgres', '-d', 'solectrus_production', '-tAc', anything
      )
    end

    it 'reports a restore that came back with fewer tables' do
      upgrade.instance_variable_set(:@expected_tables, 5)
      allow(upgrade).to receive(:count_tables).and_return(2)

      expect { upgrade.send(:verify_restore!) }.to raise_error(
        described_class::UpgradeError, /5/
      )
    end
  end

  # The dump in prepare! can fail because the container went away while it ran —
  # an environment hiccup, not something HELIOS did. Nothing would start
  # PostgreSQL again then, and the stack sits without a database until someone
  # notices (in the field: the next backup refusing to run).
  describe '#call (service left down by an aborted upgrade)' do
    subject(:call) { upgrade.call }

    let(:upgrade) { described_class.new }

    before do
      allow(upgrade).to receive(:prepare!).and_raise(
        described_class::UpgradeError, 'dump incomplete'
      )
      allow(Orchestration::Container).to receive(:invalidate_cache)
      allow(Orchestration::Runner).to receive(:start)
    end

    def stub_container(running:)
      container = instance_double(Orchestration::Container, running?: running)
      allow(Orchestration::Container).to receive(:find).with('postgresql').and_return(container)
    end

    it 'starts PostgreSQL again and still reports the failure' do
      stub_container(running: false)

      expect { call }.to raise_error(described_class::UpgradeError, /dump incomplete/)
      expect(Orchestration::Runner).to have_received(:start).with('postgresql')
    end

    it 'leaves a still-running PostgreSQL alone' do
      stub_container(running: true)

      expect { call }.to raise_error(described_class::UpgradeError)
      expect(Orchestration::Runner).not_to have_received(:start)
    end

    # Once the data directory has been wiped, the dump is the only complete copy
    # and #rollback! owns the recovery. A half-rebuilt cluster must not come up
    # and let the dashboard write into it.
    it 'does not start a cluster whose data directory was already wiped' do
      stub_container(running: false)
      upgrade.instance_variable_set(:@data_directory_touched, true)

      expect { call }.to raise_error(described_class::UpgradeError)
      expect(Orchestration::Runner).not_to have_received(:start)
    end
  end
end
