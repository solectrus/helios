RSpec.describe CsvImportRunner::CoveredDates do
  let(:root) { Dir.mktmpdir }

  after { FileUtils.remove_entry(root) }

  def write(*relative_paths)
    relative_paths.each do |rel|
      path = File.join(root, rel)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, '')
    end
  end

  describe '.scan' do
    it 'returns nil for an empty directory (nothing to scope)' do
      expect(described_class.scan(root)).to be_nil
    end

    it 'returns the seven ISO-week days for a SENEC week file with serial prefix' do
      write('S1234567890-week-22-2026.csv')

      expect(described_class.scan(root))
        .to eq([Date.new(2026, 5, 25), Date.new(2026, 5, 26), Date.new(2026, 5, 27),
                Date.new(2026, 5, 28), Date.new(2026, 5, 29), Date.new(2026, 5, 30),
                Date.new(2026, 5, 31)])
    end

    it 'merges and deduplicates dates across multiple SENEC weeks in subfolders' do
      write('2024/week-01-2024.csv', '2024/week-02-2024.csv')

      dates = described_class.scan(root)
      expect(dates.first).to eq(Date.new(2024, 1, 1))
      expect(dates.last).to eq(Date.new(2024, 1, 14))
      expect(dates.size).to eq(14)
    end

    it 'extracts a single day from a Sungrow Tagesbericht file' do
      write('Tagesbericht_20230621.csv')

      expect(described_class.scan(root)).to eq([Date.new(2023, 6, 21)])
    end

    it 'mixes SENEC and Sungrow files in the same upload' do
      write('S123-week-22-2026.csv', 'Tagesbericht_20260601.csv')

      expect(described_class.scan(root)).to include(Date.new(2026, 5, 25), Date.new(2026, 6, 1))
    end

    it 'falls back to nil if any filename cannot be classified (SolarEdge, custom names)' do
      write('S123-week-22-2026.csv', 'solar-edge-export.csv')

      expect(described_class.scan(root)).to be_nil
    end

    it 'falls back to nil when an ISO week number is invalid for its year' do
      write('week-53-2023.csv') # 2023 only has 52 ISO weeks

      expect(described_class.scan(root)).to be_nil
    end

    it 'falls back to nil when a Sungrow date is impossible' do
      write('Tagesbericht_20230230.csv') # 30 Feb

      expect(described_class.scan(root)).to be_nil
    end
  end
end
