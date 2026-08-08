RSpec.describe CsvImportRunner::LogParser do
  # Canary log captured from csv-importer 0dd4738 onward (AppLogger emits
  # bare `msg\n` without timestamp or severity prefix). If this fixture
  # stops matching the patterns, the importer's stdout format has drifted
  # and the live progress / success counter will silently break. Bump the
  # importer image deliberately and re-record this sample.
  let(:sample_log) do
    <<~LOG
      CSV importer for SOLECTRUS, Version 0.6.0, built at 2026-05-28T11:29:36.650Z
      https://github.com/solectrus/csv-importer
      Using Ruby 4.0.5 on platform aarch64-linux-musl
      Pushing to InfluxDB at http://influxdb:8086, bucket solectrus
      Using time zone Europe/Berlin
      Importing data from /data ...
      Imported /data/Statistische Daten/2025/S1234567890-week-10-2025.csv (SenecAdapter, 2006 rows)
      Imported /data/Statistische Daten/2025/S1234567890-week-11-2025.csv (SenecAdapter, 2007 rows)
      Imported /data/Statistische Daten/2025/S1234567890-week-12-2025.csv (SenecAdapter, 2005 rows)
      Imported 3 files
    LOG
  end

  describe '.progress' do
    it 'counts completed files via the per-file Imported line' do
      expect(described_class.progress(sample_log)[:done]).to eq(3)
    end

    it 'tolerates an empty log without raising' do
      expect(described_class.progress('')).to eq(done: 0)
    end

    it 'does not count the final summary line as a completed file' do
      expect(described_class.progress('Imported 3 files')).to eq(done: 0)
    end

    it 'still counts the legacy points wording' do
      legacy = 'Imported /data/foo.csv (SenecRecord, 2006 points)'

      expect(described_class.progress(legacy)[:done]).to eq(1)
    end
  end

  describe '.total_files' do
    it 'extracts the count from the final summary line' do
      expect(described_class.total_files(sample_log)).to eq(3)
    end

    it 'handles the singular variant' do
      expect(described_class.total_files('Imported 1 file')).to eq(1)
    end

    it 'returns 0 when the summary line is missing' do
      expect(described_class.total_files('whatever')).to eq(0)
    end

    it 'does not pick up the per-file Imported line as a total' do
      per_file = 'Imported /data/foo.csv (SenecAdapter, 50 rows)'

      expect(described_class.total_files(per_file)).to eq(0)
    end
  end
end
