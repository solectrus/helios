RSpec.describe ConfigurationMigrator do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:path) { File.join(tmp_dir, 'config.yaml') }

  # Stand-in for a registered migration. Lets the migrator be exercised
  # end-to-end without depending on whichever real migrations happen to be
  # in the registry.
  let(:fake_migration) do
    Class.new do
      def self.version = 1

      def up(data)
        data['migrated'] = true
        data
      end
    end
  end

  after { FileUtils.remove_entry(tmp_dir) }

  def write_yaml(data)
    File.write(path, YAML.dump(data))
  end

  def read_yaml
    YAML.safe_load_file(path, permitted_classes: [Date])
  end

  describe '#run!' do
    context 'when the file does not exist' do
      it 'returns :missing without writing anything' do
        expect(described_class.new(path).run!).to eq(:missing)
        expect(File.exist?(path)).to be(false)
      end
    end

    context 'when no migrations are pending' do
      before do
        allow(ConfigurationMigrations).to receive_messages(pending: [], current_version: 0)
        write_yaml('system' => { 'timezone' => 'Europe/Berlin' })
      end

      it 'returns :current and leaves the file untouched' do
        before_mtime = File.mtime(path)
        expect(described_class.new(path).run!).to eq(:current)
        expect(File.mtime(path)).to eq(before_mtime)
      end

      it 'creates no backup' do
        described_class.new(path).run!
        expect(Dir.children(tmp_dir).grep(/\.bak\z/)).to be_empty
      end
    end

    context 'when migrations are pending against a legacy file (no version key)' do
      before do
        allow(ConfigurationMigrations).to receive_messages(
          pending: [fake_migration],
          current_version: 1,
        )
        write_yaml('system' => { 'timezone' => 'Europe/Berlin' })
      end

      it 'runs the pending migrations and stamps the current version' do
        expect(described_class.new(path).run!).to eq(:migrated)
        result = read_yaml
        expect(result['_schema_version']).to eq(1)
        expect(result['migrated']).to be(true)
      end

      it 'leaves no backup behind once the migration has succeeded' do
        described_class.new(path).run!
        backups = Dir.children(tmp_dir).grep(/\.pre-migration-\d+\.bak\z/)
        expect(backups).to be_empty
      end
    end

    context 'when a migration raises' do
      let(:failing_migration) do
        Class.new do
          def self.version = 1
          def up(_data) = raise 'boom'
        end
      end

      before do
        allow(ConfigurationMigrations).to receive_messages(
          pending: [failing_migration],
          current_version: 1,
        )
        write_yaml('system' => { 'timezone' => 'Europe/Berlin' })
      end

      it 'preserves the timestamped backup so the original can be recovered' do
        expect { described_class.new(path).run! }.to raise_error('boom')
        backups = Dir.children(tmp_dir).grep(/\.pre-migration-\d+\.bak\z/)
        expect(backups.size).to eq(1)
      end

      it 'leaves the original file untouched' do
        expect { described_class.new(path).run! }.to raise_error('boom')
        expect(read_yaml).to eq('system' => { 'timezone' => 'Europe/Berlin' })
      end
    end

    context 'when the file already has a higher schema version' do
      before do
        allow(ConfigurationMigrations).to receive_messages(pending: [], current_version: 1)
        write_yaml('system' => { 'timezone' => 'Europe/Berlin' }, '_schema_version' => 99)
      end

      it 'leaves the higher version intact and does not migrate' do
        expect(described_class.new(path).run!).to eq(:current)
        expect(read_yaml['_schema_version']).to eq(99)
      end
    end
  end
end
