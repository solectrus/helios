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

  # A killed HELIOS (restart, reboot, OOM) takes the upgrade job with it, so
  # none of the in-process rollback paths run. What is left is the journal on
  # disk; these examples pin what the next boot makes of each phase.
  describe '.recover!' do
    subject(:recover!) { described_class.recover! }

    let(:journal) { Orchestration::PostgresqlUpgrade::Journal }
    let(:dump_path) { File.join(config_yaml_dir, 'postgresql-upgrade-20260731120000.sql') }

    before do
      with_config_yaml('postgresql' => { 'image' => 'postgres:18-alpine' })
      allow(Orchestration::Container).to receive(:invalidate_cache)
      allow(Orchestration::Container).to receive(:find).with('postgresql').and_return(
        instance_double(Orchestration::Container, running?: true),
      )
      allow(Orchestration::Runner).to receive(:start)
      allow(Orchestration::Runner).to receive(:stop)
      allow(Orchestration::AffectedServices).to receive(:update_deployed_hash!)
      allow(Export::Builder).to receive(:new).and_return(
        instance_double(Export::Builder, write!: true),
      )
    end

    def open_journal!(phase)
      entry = journal.start!(
        dump_path:,
        previous_image: 'postgres:17-alpine',
        previous_pgdata: nil,
        previous_major: 17,
        expected_tables: 3,
      )
      entry.advance!(phase) unless phase == :preparing
      entry
    end

    def write_dump!(complete: true)
      body = "CREATE TABLE widgets;\n"
      body += "--\n-- #{described_class::DUMP_COMPLETE_MARKER}\n--\n" if complete
      File.write(dump_path, body)
    end

    it 'does nothing when no upgrade was interrupted' do
      expect(recover!).to be(false)
    end

    context 'when it was killed while dumping' do
      before do
        open_journal!(:preparing)
        write_dump!(complete: false)
      end

      it 'reports that nothing happened and drops the partial dump' do
        expect { recover! }.to raise_error(described_class::UpgradeError, /interrupted before any data/i)

        aggregate_failures do
          expect(File).not_to exist(dump_path)
          expect(journal.load).to be_nil
        end
      end
    end

    context 'when it was killed after the image was bumped' do
      before do
        open_journal!(:migrating)
        write_dump!
      end

      # The old cluster is still on disk. Leaving the new major configured
      # would have PostgreSQL refuse to start on the next recreate.
      it 'reverts to the previous major and reports the interruption' do
        expect { recover! }.to raise_error(described_class::UpgradeError, /previous version 17|Version 17/)

        aggregate_failures do
          expect(Configuration.current.postgresql.image).to eq('postgres:17-alpine')
          expect(Orchestration::Runner).to have_received(:start).with('postgresql')
          expect(File).not_to exist(dump_path)
          expect(journal.load).to be_nil
        end
      end
    end

    context 'when it was killed with an emptied data directory' do
      before do
        open_journal!(:rebuilding)
        write_dump!
      end

      it 'rebuilds the cluster from the dump and finishes the upgrade' do
        upgrade = described_class.new
        allow(described_class).to receive(:new).and_return(upgrade)
        allow(upgrade).to receive_messages(
          wipe_data_directory!: true,
          wait_until_ready!: true,
          restore_dump!: true,
          count_tables: 3,
          reconcile_stack!: true,
        )

        expect(recover!).to be(true)

        aggregate_failures do
          expect(upgrade).to have_received(:restore_dump!)
          expect(Configuration.current.postgresql.image).to eq('postgres:18-alpine')
          expect(File).not_to exist(dump_path)
          expect(journal.load).to be_nil
        end
      end

      # Nothing left to rebuild from — retrying this on every boot would not
      # change the outcome, so the journal goes and the user is told.
      it 'gives up when the dump is gone' do
        FileUtils.rm_f(dump_path)

        expect { recover! }.to raise_error(described_class::UpgradeError, /backup|Datensicherung/i)

        expect(journal.load).to be_nil
      end

      it 'gives up when the dump is truncated' do
        write_dump!(complete: false)

        expect { recover! }.to raise_error(described_class::UpgradeError)

        expect(journal.load).to be_nil
      end
    end

    context 'when it was killed after the restore was verified' do
      before do
        open_journal!(:finishing)
        write_dump!
      end

      it 'only reconciles the stack and closes the journal' do
        upgrade = described_class.new
        allow(described_class).to receive(:new).and_return(upgrade)
        allow(upgrade).to receive(:reconcile_stack!)

        expect(recover!).to be(true)

        aggregate_failures do
          expect(upgrade).to have_received(:reconcile_stack!)
          expect(File).not_to exist(dump_path)
          expect(journal.load).to be_nil
        end
      end
    end

    # Starting a second upgrade on top of a half-migrated stack would dump a
    # cluster that may not even be the original one.
    it 'refuses a fresh upgrade while a recovery is pending' do
      open_journal!(:rebuilding)

      expect { described_class.call }.to raise_error(
        described_class::UpgradeError, /interrupted|unterbrochen/i
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
