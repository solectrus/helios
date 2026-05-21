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

    it 'reads the file list from the archive' do
      write_backup(
        'solectrus-backup-20260508-110000.tar',
        archive: { 'helios/config.yaml' => 'system: {}' },
      )

      backup = described_class.all.first # rubocop:disable Rails/RedundantActiveRecordAllMethod
      expect(backup.files.map(&:name)).to contain_exactly('helios/config.yaml')
    end

    it 'exposes PostgreSQL and InfluxDB sizes from the archive' do
      write_backup(
        'solectrus-backup-20260508-110000.tar',
        archive: {
          'solectrus-postgresql-backup-2026-05-08.sql.gz' => 'p' * 100,
          'solectrus-influxdb-backup-2026-05-08.tar.gz' => 'i' * 200,
          'helios/config.yaml' => 'system: {}',
        },
      )

      backup = described_class.all.first # rubocop:disable Rails/RedundantActiveRecordAllMethod
      expect(backup.postgresql_bytes).to eq(100)
      expect(backup.influxdb_bytes).to eq(200)
    end

    it 'returns created_at in the active Time.zone' do
      Time.use_zone('Europe/Berlin') do
        # File mtimes are stored as UTC by the OS; the repository must convert to Time.zone
        # so views render in the user-configured timezone (e.g. backup at 07:40 Berlin must
        # not appear as 05:40).
        mtime = Time.utc(2026, 7, 1, 5, 40)
        write_backup('solectrus-backup-20260701-074000.tar', mtime: mtime)

        backup = described_class.all.first # rubocop:disable Rails/RedundantActiveRecordAllMethod
        expect(backup.created_at.zone).to eq('CEST')
        expect(backup.created_at.strftime('%H:%M')).to eq('07:40')
      end
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
    it 'removes the archive and any legacy manifest sidecar' do
      filename = 'solectrus-backup-20260508-110000.tar'
      write_backup(filename)
      File.write(File.join(backups_dir, "#{filename}.json"), '{}') # legacy sidecar

      described_class.destroy!(filename)

      expect(File).not_to exist(File.join(backups_dir, filename))
      expect(File).not_to exist(File.join(backups_dir, "#{filename}.json"))
    end

    it 'works when no legacy sidecar exists' do
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

    it 'removes any legacy manifest sidecar alongside the backup file' do
      filename = 'solectrus-backup-20260508-110000.tar'
      write_backup(filename)
      File.write(File.join(backups_dir, "#{filename}.json"), '{}') # legacy sidecar

      described_class.prune!(keep: 0)

      expect(File).not_to exist(File.join(backups_dir, filename))
      expect(File).not_to exist(File.join(backups_dir, "#{filename}.json"))
    end
  end

  describe 'image versions' do
    it 'reads the InfluxDB and PostgreSQL images from the archived config.yaml' do
      write_backup(
        'solectrus-backup-20260508-110000.tar',
        archive: {
          'helios/config.yaml' => "influxdb:\n  image: influxdb:2.6-alpine\npostgresql:\n  image: postgres:13-alpine\n",
        },
      )

      backup = described_class.find!('solectrus-backup-20260508-110000.tar')
      expect(backup.influxdb_image).to eq('influxdb:2.6-alpine')
      expect(backup.postgresql_image).to eq('postgres:13-alpine')
    end

    it 'is nil when config.yaml carries no image' do
      write_backup('solectrus-backup-20260508-110000.tar')

      backup = described_class.find!('solectrus-backup-20260508-110000.tar')
      expect(backup.influxdb_image).to be_nil
      expect(backup.postgresql_image).to be_nil
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

  describe '.storage' do
    it 'returns the local adapter when destination is unset' do
      expect(described_class.storage).to eq(BackupRepository::Local)
    end

    it 'returns the local adapter when destination is explicitly "local"' do
      with_config_yaml('backup' => { 'destination' => 'local' })
      expect(described_class.storage).to eq(BackupRepository::Local)
    end

    it 'returns the external adapter when destination is "external"' do
      with_config_yaml('backup' => { 'destination' => 'external', 'external_path' => '/mnt/backups' })
      expect(described_class.storage).to eq(BackupRepository::External)
    end

    it 'returns the S3 adapter when destination is "s3"' do
      with_config_yaml('backup' => { 'destination' => 's3', 'aws_bucket' => 'b',
                                     'aws_access_key_id' => 'k', 'aws_secret_access_key' => 's',
                                     'aws_region' => 'eu-central-1' })
      expect(described_class.storage).to eq(BackupRepository::S3)
    end
  end

  describe '.local?, .external?, .s3?, .remote?' do
    it 'classifies the configured destination' do
      with_config_yaml('backup' => { 'destination' => 'local' })
      expect([described_class.local?, described_class.external?, described_class.s3?, described_class.remote?])
        .to eq([true, false, false, false])
    end

    it 'flags external as remote' do
      with_config_yaml('backup' => { 'destination' => 'external', 'external_path' => '/mnt/x' })
      expect([described_class.local?, described_class.external?, described_class.s3?, described_class.remote?])
        .to eq([false, true, false, true])
    end

    it 'flags s3 as remote' do
      with_config_yaml('backup' => { 'destination' => 's3', 'aws_bucket' => 'b',
                                     'aws_access_key_id' => 'k', 'aws_secret_access_key' => 's', 'aws_region' => 'eu' })
      expect([described_class.local?, described_class.external?, described_class.s3?, described_class.remote?])
        .to eq([false, false, true, true])
    end
  end

  def write_backup(filename, archive: { 'helios/config.yaml' => 'system: {}' }, mtime: nil)
    FileUtils.mkdir_p(backups_dir)
    path = File.join(backups_dir, filename)
    File.binwrite(path, tar_archive(archive))
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
