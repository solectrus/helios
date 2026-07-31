RSpec.describe Orchestration::PostgresqlUpgrade::Journal do
  before { with_config_yaml }

  def attributes
    {
      dump_path: '/data/postgresql-upgrade-20260731120000.sql',
      previous_image: 'postgres:17-alpine',
      previous_pgdata: nil,
      previous_major: 17,
      expected_tables: 42,
    }
  end

  describe '.start!' do
    it 'opens the journal in the first phase and writes it through' do
      described_class.start!(**attributes)

      loaded = described_class.load
      expect(loaded).to have_attributes(
        phase: :preparing,
        dump_path: attributes[:dump_path],
        previous_image: 'postgres:17-alpine',
        previous_major: 17,
        expected_tables: 42,
      )
    end
  end

  describe '.load' do
    it 'is nil without a journal' do
      expect(described_class.load).to be_nil
    end

    # A journal HELIOS cannot make sense of must not keep it from booting —
    # the recovery is skipped instead.
    it 'is nil for an unreadable journal' do
      FileUtils.mkdir_p(File.dirname(described_class.path))
      File.write(described_class.path, 'not json')

      expect(described_class.load).to be_nil
    end

    it 'is nil for an unknown phase' do
      FileUtils.mkdir_p(File.dirname(described_class.path))
      File.write(described_class.path, JSON.generate(phase: 'whatever'))

      expect(described_class.load).to be_nil
    end
  end

  describe '#advance!' do
    it 'persists the new phase immediately' do
      described_class.start!(**attributes).advance!(:rebuilding)

      expect(described_class.load.phase).to eq(:rebuilding)
    end

    it 'keeps the recorded attributes' do
      described_class.start!(**attributes).advance!(:migrating)

      expect(described_class.load.previous_image).to eq('postgres:17-alpine')
    end

    it 'refuses an unknown phase' do
      journal = described_class.start!(**attributes)

      expect { journal.advance!(:nonsense) }.to raise_error(ArgumentError)
    end
  end

  describe '#clear!' do
    it 'removes the journal' do
      described_class.start!(**attributes).clear!

      expect(described_class.load).to be_nil
    end
  end
end
