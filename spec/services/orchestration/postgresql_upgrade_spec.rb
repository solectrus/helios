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

  # A cluster can hold every table and still be useless: PostgreSQL 13 and
  # older store the superuser password MD5-encrypted, and from 14 on the
  # image's pg_hba.conf demands scram-sha-256, which cannot fall back to an
  # MD5 secret. Carrying that hash over in the dump left a database no service
  # could log in to — invisible to every other check, since HELIOS talks to
  # PostgreSQL over the Unix socket, which the image trusts.
  describe 'password authentication across majors' do
    let(:upgrade) { described_class.new }

    it 'dumps without the role passwords, so the new cluster keeps its own' do
      allow(Orchestration::Runner).to receive(:compose_exec_streaming).and_return(['', 0])
      allow(upgrade).to receive(:dump_complete?).and_return(true)

      upgrade.send(:create_dump!)

      expect(Orchestration::Runner).to have_received(:compose_exec_streaming).with(
        'postgresql', 'pg_dumpall', '-U', 'postgres', '--no-role-passwords', out_path: anything
      )
    end

    it 'probes the login over TCP, the path the other services use' do
      allow(Orchestration::Runner).to receive(:compose_exec).and_return(['1', '', 0])

      upgrade.send(:verify_authentication!)

      expect(Orchestration::Runner).to have_received(:compose_exec).with(
        'postgresql', 'sh', '-c', a_string_matching(/PGPASSWORD.*psql -h "\$\(hostname\)"/m)
      )
    end

    it 'fails the upgrade when the configured password no longer authenticates' do
      allow(Orchestration::Runner).to receive(:compose_exec).and_return(
        ['', 'FATAL: password authentication failed for user "postgres"', 2],
      )

      expect { upgrade.send(:verify_authentication!) }.to raise_error(
        described_class::UpgradeError, /password authentication failed/
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
          verify_authentication!: true,
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

      # The resumed rebuild fails just like the original one would: the
      # rollback takes over, and since it rebuilds from the very same dump it
      # fails too. The dump then has to survive, it is the only copy left.
      it 'hands a failing rebuild over to the rollback and keeps the dump' do
        upgrade = described_class.new
        allow(described_class).to receive(:new).and_return(upgrade)
        allow(upgrade).to receive_messages(wipe_data_directory!: true, wait_until_ready!: true)
        allow(upgrade).to receive(:restore_dump!).and_raise(StandardError, 'psql gone')

        expect { recover! }.to raise_error(described_class::UpgradeError, /psql gone/)

        expect(Configuration.current.postgresql.image).to eq('postgres:17-alpine')
        expect(File).to exist(dump_path)
      end
    end

    # Whatever goes wrong during a recovery, the user gets one UpgradeError —
    # a raw exception here would surface as a 500 on the start page.
    it 'wraps an unexpected failure' do
      open_journal!(:finishing)
      upgrade = described_class.new
      allow(described_class).to receive(:new).and_return(upgrade)
      allow(upgrade).to receive(:reconcile_stack!).and_raise(TypeError, 'boom')

      expect { recover! }.to raise_error(described_class::UpgradeError, /TypeError: boom/)
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

  # The full upgrade, with every Docker call stubbed but the real journal,
  # dump file and config rewrite. Pins the order of the destructive steps and
  # what each failure leaves behind.
  describe '#call' do
    subject(:call) { upgrade.call }

    let(:upgrade) { described_class.new }
    let(:table_count) { '5' }
    let(:dump_path) { upgrade.send(:dump_path) }

    before do
      with_config_yaml('postgresql' => { 'image' => 'postgres:17-alpine' })
      allow(Orchestration::Container).to receive(:invalidate_cache)
      stub_postgresql_container(running: true)
      allow(Orchestration::Container).to receive(:all).and_return([])
      allow(Orchestration::Runner).to receive_messages(start: nil, stop: nil, pull: nil, reconcile: nil)
      allow(Orchestration::AffectedServices).to receive(:update_deployed_hash!)
      allow(Export::Builder).to receive(:new).and_return(instance_double(Export::Builder, write!: true))
      allow(Compose).to receive(:load).and_return(
        instance_double(Compose::File, services: Compose::ServiceCollection.new(
          'postgresql' => { 'image' => 'postgres:18-alpine' },
        )),
      )

      # psql/pg_isready/auth probe all answer "fine"; count_tables reports the
      # same number before and after, so the restore verifies.
      allow(Orchestration::Runner).to receive_messages(compose_exec: [table_count, '', 0],
                                                       compose_run: ['', '', 0])
      allow(Orchestration::Runner).to receive(:compose_exec_streaming) do |*, **kwargs|
        if kwargs[:out_path]
          File.write(dump_path,
                     "CREATE TABLE widgets;\n-- #{described_class::DUMP_COMPLETE_MARKER}\n")
        end
        ['', 0]
      end
    end

    it 'dumps, wipes and rebuilds on the target image' do
      expect(call).to be(true)

      expect(Configuration.current.postgresql.image).to eq(described_class.target_image)
      expect(Orchestration::Runner).to have_received(:pull).with(service: 'postgresql')
      # The data directory is emptied from inside a throwaway container, and
      # only after the dump is known to be complete.
      expect(Orchestration::Runner).to have_received(:compose_run)
        .with('postgresql', '-c', a_string_including('find /var/lib/postgresql '), entrypoint: 'sh')
      expect(Orchestration::Runner).to have_received(:reconcile).with(['postgresql'])
    end

    it 'leaves neither a journal nor a dump behind' do
      call

      expect(described_class).not_to be_interrupted
      expect(File).not_to exist(dump_path)
    end

    context 'when the dump command fails' do
      before do
        allow(Orchestration::Runner).to receive(:compose_exec_streaming).and_return(['permission denied', 1])
      end

      it 'aborts before anything is changed and removes the partial dump' do
        expect { call }.to raise_error(described_class::UpgradeError, /permission denied/)

        expect(Configuration.current.postgresql.image).to eq('postgres:17-alpine')
        expect(File).not_to exist(dump_path)
      end
    end

    context 'when the dump is truncated' do
      before do
        allow(Orchestration::Runner).to receive(:compose_exec_streaming) do |*, **kwargs|
          File.write(dump_path, "CREATE TABLE widgets;\n") if kwargs[:out_path]
          ['', 0]
        end
      end

      it 'refuses to migrate from an incomplete dump' do
        expect { call }.to raise_error(described_class::UpgradeError)

        expect(Orchestration::Runner).not_to have_received(:pull)
      end
    end

    # The restore is verified against the table count taken before the dump; a
    # mismatch rolls the stack back onto the previous major.
    context 'when the restored cluster holds fewer tables' do
      before do
        counts = [[table_count, '', 0], ['2', '', 0]]
        allow(Orchestration::Runner).to receive(:compose_exec) do |_service, *command|
          command.include?('pg_isready') ? ['', '', 0] : (counts.shift || ['2', '', 0])
        end
      end

      it 'rolls back to the previous image and reports it' do
        expect { call }.to raise_error(described_class::UpgradeError, /17/)

        expect(Configuration.current.postgresql.image).to eq('postgres:17-alpine')
        expect(File).not_to exist(dump_path)
        expect(described_class).not_to be_interrupted
      end
    end

    # Anything unexpected (a bug, a gem raising) must still reach the user as
    # an UpgradeError, and PostgreSQL must come back up.
    context 'when a step fails with an error the upgrade does not know' do
      before { allow(upgrade).to receive(:prepare!).and_raise(TypeError, 'boom') }

      it 'wraps it and starts PostgreSQL again' do
        stub_postgresql_container(running: false)

        expect { call }.to raise_error(described_class::UpgradeError, /TypeError: boom/)
        expect(Orchestration::Runner).to have_received(:start).with('postgresql')
      end

      # Docker being unreachable is exactly why the service is down; the
      # original failure is what the user needs to see, not a second one.
      it 'keeps the original error when the restart fails too' do
        stub_postgresql_container(running: false)
        allow(Orchestration::Runner).to receive(:start).and_raise(StandardError, 'docker gone')

        expect { call }.to raise_error(described_class::UpgradeError, /TypeError: boom/)
      end
    end

    # Before the data directory is emptied, reverting the compose files and
    # starting the old container is all the rollback has to do.
    context 'when the image bump fails before anything was wiped' do
      before { allow(Orchestration::Runner).to receive(:pull).and_raise(StandardError, 'no such image') }

      it 'restarts the previous container without rebuilding the cluster' do
        expect { call }.to raise_error(described_class::UpgradeError, /17/)

        expect(Configuration.current.postgresql.image).to eq('postgres:17-alpine')
        expect(Orchestration::Runner).to have_received(:start).with('postgresql')
        expect(Orchestration::Runner).not_to have_received(:compose_run)
      end
    end

    context 'when the data directory cannot be emptied' do
      before { allow(Orchestration::Runner).to receive(:compose_run).and_return(['', 'permission denied', 1]) }

      it 'reports the wipe failure' do
        expect { call }.to raise_error(described_class::UpgradeError, /permission denied/)
      end
    end

    context 'when the new server never accepts connections' do
      before do
        stub_const("#{described_class}::READY_TIMEOUT", 0.02)
        stub_const("#{described_class}::POLL_INTERVAL", 0.01)
        allow(Orchestration::Runner).to receive(:compose_exec) do |_service, *command|
          command.include?('pg_isready') ? ['', '', 1] : [table_count, '', 0]
        end
      end

      it 'gives up after the ready timeout' do
        expect { call }.to raise_error(described_class::UpgradeError)
      end
    end

    context 'when the restore itself fails' do
      before do
        allow(Orchestration::Runner).to receive(:compose_exec_streaming) do |*, **kwargs|
          if kwargs[:out_path]
            File.write(dump_path, "CREATE TABLE widgets;\n-- #{described_class::DUMP_COMPLETE_MARKER}\n")
            ['', 0]
          else
            ['could not connect', 1]
          end
        end
      end

      it 'reports what psql said' do
        expect { call }.to raise_error(described_class::UpgradeError, /could not connect/)
      end
    end

    # A rollback that fails itself leaves the journal and the dump in place —
    # the next boot retries, and the user still has the data.
    context 'when the rollback fails as well' do
      before do
        allow(Orchestration::Runner).to receive(:start).and_raise(StandardError, 'docker gone')
      end

      it 'keeps the dump and points at it' do
        expect { call }.to raise_error(described_class::UpgradeError, /#{Regexp.escape(dump_path)}/)

        expect(File).to exist(dump_path)
        expect(described_class).to be_interrupted
      end
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

  def stub_postgresql_container(running:)
    allow(Orchestration::Container).to receive(:find).with('postgresql').and_return(
      instance_double(Orchestration::Container, running?: running, version: '17.5'),
    )
  end
end
