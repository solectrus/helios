require 'rubygems/package'

RSpec.describe BackupRepository do
  let(:data_path) { Dir.mktmpdir }
  let(:backups_dir) { File.join(data_path, 'helios', 'backups') }

  before do
    allow(Rails.configuration).to receive(:data_path).and_return(data_path)
    FileUtils.mkdir_p(File.join(data_path, 'helios'))
  end

  after { FileUtils.remove_entry(data_path) }

  describe '.all' do
    it 'returns Backup entries for each archive, newest first' do
      write_backup('solectrus-backup-20260508-110000.tar')
      write_backup('solectrus-backup-20260508-120000.tar')

      filenames = described_class.all.map(&:filename)
      expect(filenames).to eq([
                                'solectrus-backup-20260508-120000.tar',
                                'solectrus-backup-20260508-110000.tar',
                              ])
    end

    it 'reads file sizes from a manifest when present' do
      write_backup(
        'solectrus-backup-20260508-110000.tar',
        manifest: { entries: [{ name: 'helios/config.yaml', bytes: 42 }] },
      )

      backup = described_class.all.first # rubocop:disable Rails/RedundantActiveRecordAllMethod
      expect(backup.files).to contain_exactly(
        described_class::Entry.new(name: 'helios/config.yaml', bytes: 42),
      )
    end

    it 'falls back to scanning the archive when the manifest is missing' do
      write_backup(
        'solectrus-backup-20260508-110000.tar',
        archive: { 'helios/config.yaml' => 'system: {}' },
      )

      backup = described_class.all.first # rubocop:disable Rails/RedundantActiveRecordAllMethod
      expect(backup.files.map(&:name)).to contain_exactly('helios/config.yaml')
    end

    it 'exposes PostgreSQL and InfluxDB sizes via the manifest' do
      write_backup(
        'solectrus-backup-20260508-110000.tar',
        manifest: { entries: [
          { name: 'solectrus-postgresql-backup-2026-05-08.sql.gz', bytes: 100 },
          { name: 'solectrus-influxdb-backup-2026-05-08.tar.gz', bytes: 200 },
          { name: 'helios/config.yaml', bytes: 10 },
        ] },
      )

      backup = described_class.all.first # rubocop:disable Rails/RedundantActiveRecordAllMethod
      expect(backup.postgresql_bytes).to eq(100)
      expect(backup.influxdb_bytes).to eq(200)
    end

    it 'ignores partial files and unrelated entries' do
      write_backup('solectrus-backup-20260508-110000.tar')
      FileUtils.mkdir_p(backups_dir)
      File.write(File.join(backups_dir, 'solectrus-backup-20260508-120000.tar.part'), 'in-progress')
      File.write(File.join(backups_dir, 'README.txt'), 'hello')

      filenames = described_class.all.map(&:filename)
      expect(filenames).to contain_exactly('solectrus-backup-20260508-110000.tar')
    end
  end

  describe '.find!' do
    it 'returns a Backup for an existing filename' do
      write_backup('solectrus-backup-20260508-110000.tar')

      backup = described_class.find!('solectrus-backup-20260508-110000.tar')
      expect(backup.filename).to eq('solectrus-backup-20260508-110000.tar')
    end

    it 'raises NotFound for missing files' do
      expect do
        described_class.find!('solectrus-backup-20260508-110000.tar')
      end.to raise_error(described_class::NotFound)
    end

    it 'rejects filenames not matching the pattern' do
      expect { described_class.find!('../etc/passwd') }.to raise_error(described_class::NotFound)
    end
  end

  describe '.destroy!' do
    it 'removes the archive and its manifest' do
      filename = 'solectrus-backup-20260508-110000.tar'
      write_backup(filename, manifest: { entries: [] })

      described_class.destroy!(filename)

      expect(File).not_to exist(File.join(backups_dir, filename))
      expect(File).not_to exist(File.join(backups_dir, "#{filename}.json"))
    end

    it 'works when the manifest is missing' do
      filename = 'solectrus-backup-20260508-110000.tar'
      write_backup(filename)

      expect { described_class.destroy!(filename) }.not_to raise_error
      expect(File).not_to exist(File.join(backups_dir, filename))
    end

    it 'raises NotFound for a missing backup' do
      expect do
        described_class.destroy!('solectrus-backup-20260508-110000.tar')
      end.to raise_error(described_class::NotFound)
    end

    it 'rejects filenames not matching the pattern' do
      expect { described_class.destroy!('../etc/passwd') }.to raise_error(described_class::NotFound)
    end
  end

  describe '.prune!' do
    it 'keeps only the four most recent backups (MAX_BACKUPS - 1)' do
      now = Time.zone.now
      6.times do |i|
        write_backup("solectrus-backup-20260508-11000#{i}.tar", mtime: now + i.seconds)
      end

      described_class.prune!

      expect(described_class.all.map(&:filename)).to eq(%w[
                                                          solectrus-backup-20260508-110005.tar
                                                          solectrus-backup-20260508-110004.tar
                                                          solectrus-backup-20260508-110003.tar
                                                          solectrus-backup-20260508-110002.tar
                                                        ])
    end

    it 'removes the manifest alongside the backup file' do
      filename = 'solectrus-backup-20260508-110000.tar'
      write_backup(filename, manifest: { entries: [] })

      described_class.prune!(keep: 0)

      expect(File).not_to exist(File.join(backups_dir, filename))
      expect(File).not_to exist(File.join(backups_dir, "#{filename}.json"))
    end
  end

  describe 'restored_at' do
    it 'is nil when the manifest has no restored_at' do
      write_backup('solectrus-backup-20260508-110000.tar', manifest: { entries: [] })

      expect(described_class.find!('solectrus-backup-20260508-110000.tar').restored_at).to be_nil
    end

    it 'is nil when no manifest exists at all' do
      write_backup('solectrus-backup-20260508-110000.tar')

      expect(described_class.find!('solectrus-backup-20260508-110000.tar').restored_at).to be_nil
    end

    it 'parses the restored_at from the manifest as a Time.zone-aware Time' do
      restored_at = '2026-05-09T08:30:00Z'
      write_backup(
        'solectrus-backup-20260508-110000.tar',
        manifest: { entries: [], restored_at: restored_at },
      )

      backup = described_class.find!('solectrus-backup-20260508-110000.tar')
      expect(backup.restored_at).to eq(Time.zone.parse(restored_at))
    end

    it 'in .all only the most recent restore keeps its restored_at' do
      write_backup(
        'solectrus-backup-20260508-110000.tar',
        manifest: { entries: [], restored_at: '2026-05-08T12:00:00Z' },
      )
      write_backup(
        'solectrus-backup-20260508-120000.tar',
        manifest: { entries: [], restored_at: '2026-05-09T08:30:00Z' },
      )
      write_backup('solectrus-backup-20260508-130000.tar', manifest: { entries: [] })

      restored_by_filename = described_class.all.to_h { |b| [b.filename, b.restored_at] }
      expect(restored_by_filename).to eq(
        'solectrus-backup-20260508-110000.tar' => nil,
        'solectrus-backup-20260508-120000.tar' => Time.zone.parse('2026-05-09T08:30:00Z'),
        'solectrus-backup-20260508-130000.tar' => nil,
      )
    end
  end

  describe '.error_message' do
    it 'returns nil when no error.txt exists' do
      expect(described_class.error_message).to be_nil
    end

    it 'returns the trimmed contents of error.txt' do
      FileUtils.mkdir_p(backups_dir)
      File.write(File.join(backups_dir, 'error.txt'), "Disk full\n")

      expect(described_class.error_message).to eq('Disk full')
    end

    it 'returns nil when error.txt is empty' do
      FileUtils.mkdir_p(backups_dir)
      File.write(File.join(backups_dir, 'error.txt'), '')

      expect(described_class.error_message).to be_nil
    end
  end

  describe '.clear_error!' do
    it 'removes error.txt' do
      FileUtils.mkdir_p(backups_dir)
      path = File.join(backups_dir, 'error.txt')
      File.write(path, 'oops')

      described_class.clear_error!

      expect(File).not_to exist(path)
    end

    it 'is a no-op when no error.txt exists' do
      expect { described_class.clear_error! }.not_to raise_error
    end
  end

  def write_backup(filename, archive: { 'helios/config.yaml' => 'system: {}' }, manifest: nil, mtime: nil)
    FileUtils.mkdir_p(backups_dir)
    path = File.join(backups_dir, filename)
    File.binwrite(path, tar_archive(archive))
    File.write("#{path}.json", JSON.generate(manifest)) if manifest
    File.utime(mtime.to_i, mtime.to_i, path) if mtime
  end

  def tar_archive(entries)
    StringIO.new.tap do |io|
      Gem::Package::TarWriter.new(io) do |tar|
        entries.each do |name, content|
          tar.add_file_simple(name, 0o644, content.bytesize) { |entry| entry.write(content) }
        end
      end
    end.string
  end
end
