RSpec.describe SupportBundle::SystemInfo::PostgresReport do
  describe '.tables' do
    let(:container) do
      instance_double(Orchestration::Container, name: 'solectrus-postgresql-1', running?: true)
    end
    let(:configuration) do
      instance_double(Configuration, postgresql: Configuration::Data.wrap('password' => 'secret123'))
    end

    before do
      allow(Orchestration::Container).to receive(:find).with('postgresql').and_return(container)
      allow(Configuration).to receive(:current).and_return(configuration)
    end

    it 'renders a table of names and row counts' do
      psql_output = "measurements|123456\nar_internal_metadata|1\nschema_migrations|42\n"
      status = instance_double(Process::Status, success?: true)
      allow(Open3).to receive(:capture2e).and_return([psql_output, status])

      result = described_class.tables

      expect(result).to include('TABLE', 'ROWS')
      expect(result).to include('measurements', '123456')
      expect(result).to include('schema_migrations', '42')
    end

    it 'passes the Postgres password from config.yaml via PGPASSWORD' do
      status = instance_double(Process::Status, success?: true)
      allow(Open3).to receive(:capture2e).and_return(['', status])

      described_class.tables

      expect(Open3).to have_received(:capture2e).with(
        'docker', 'exec', '-e', 'PGPASSWORD=secret123', 'solectrus-postgresql-1',
        'psql', '-U', 'postgres', '-d', 'solectrus_production',
        '-t', '-A', '-F', '|', '-c', kind_of(String)
      )
    end

    it 'omits PGPASSWORD when config.yaml has no postgres password' do
      allow(configuration).to receive(:postgresql).and_return(Configuration::Data.wrap({}))
      status = instance_double(Process::Status, success?: true)
      allow(Open3).to receive(:capture2e).and_return(['', status])

      described_class.tables

      expect(Open3).to have_received(:capture2e) do |*args|
        expect(args).not_to include('-e')
        expect(args.join(' ')).not_to include('PGPASSWORD')
      end
    end

    it 'reports the empty case when no tables exist' do
      status = instance_double(Process::Status, success?: true)
      allow(Open3).to receive(:capture2e).and_return(["\n", status])

      expect(described_class.tables).to eq('No tables found in solectrus_production.')
    end

    it 'surfaces psql failures with the exit code' do
      status = instance_double(Process::Status, success?: false, exitstatus: 2)
      allow(Open3).to receive(:capture2e).and_return(['FATAL: database does not exist', status])

      expect(described_class.tables).to eq('failed (exit 2): FATAL: database does not exist')
    end

    it 'short-circuits when the container is not running' do
      allow(container).to receive(:running?).and_return(false)

      expect(described_class.tables).to eq('PostgreSQL container not running.')
    end

    it 'short-circuits when the container is missing' do
      allow(Orchestration::Container).to receive(:find).with('postgresql').and_return(nil)

      expect(described_class.tables).to eq('PostgreSQL container not found.')
    end

    it 'degrades gracefully when Docker is unreachable' do
      allow(Orchestration::Container).to receive(:find)
        .and_raise(Orchestration::ConnectionError, 'socket missing')

      expect(described_class.tables).to eq('unavailable: Orchestration::ConnectionError: socket missing')
    end
  end

  describe '.parse' do
    it 'splits psql tuple-only output into [name, count] pairs' do
      output = "foo|10\nbar|20\n\n"

      expect(described_class.parse(output)).to eq([%w[foo 10], %w[bar 20]])
    end
  end
end
