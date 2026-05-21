require 'rubygems/package'

RSpec.describe BackupUploader do
  let(:data_path) { Dir.mktmpdir }
  let(:backups_dir) { File.join(data_path, 'helios', 'backups') }

  before do
    allow(Rails.configuration).to receive(:data_path).and_return(data_path)
    allow(BackupRunner).to receive(:in_progress).and_return(nil)
    allow(RestoreRunner).to receive(:in_progress).and_return(nil)
  end

  after { FileUtils.remove_entry(data_path) }

  describe '.start' do
    it 'stores the upload under the original filename when it matches the pattern' do
      uploaded = build_upload('solectrus-backup-20260507-101234.tar', valid_archive)

      described_class.start(uploaded)

      expect(File).to exist(File.join(backups_dir, 'solectrus-backup-20260507-101234.tar'))
    end

    it 'sets the mtime to the timestamp encoded in the filename' do
      uploaded = build_upload('solectrus-backup-20260507-101234.tar', valid_archive)

      described_class.start(uploaded)

      stored_path = File.join(backups_dir, 'solectrus-backup-20260507-101234.tar')
      expect(File.mtime(stored_path)).to eq(Time.zone.local(2026, 5, 7, 10, 12, 34))
    end

    it 'generates a fresh filename when the original does not match the pattern' do
      allow(Time).to receive(:current).and_return(Time.zone.local(2026, 5, 9, 14, 30, 0))
      uploaded = build_upload('migration.tar', valid_archive)

      described_class.start(uploaded)

      expect(File).to exist(File.join(backups_dir, 'solectrus-backup-20260509-143000.tar'))
    end

    it 'rejects a file with the wrong extension' do
      uploaded = build_upload('migration.zip', valid_archive)

      expect { described_class.start(uploaded) }
        .to raise_error(BackupUploader::Error, I18n.t('backups.uploader.errors.not_tar'))
    end

    it 'rejects a file that is not a tar archive' do
      uploaded = build_upload('random.tar', 'not a tar file at all')

      expect { described_class.start(uploaded) }
        .to raise_error(BackupUploader::Error, I18n.t('backups.uploader.errors.invalid_archive'))
    end

    it 'rejects an archive without a PostgreSQL dump' do
      archive = valid_archive_entries.except('solectrus-postgresql-backup-2026-05-07.sql.gz')
      uploaded = build_upload('solectrus-backup-20260507-101234.tar', tar_archive(archive))

      expect { described_class.start(uploaded) }
        .to raise_error(BackupUploader::Error, I18n.t('backups.uploader.errors.missing_postgres'))
    end

    it 'rejects an archive without an InfluxDB backup' do
      archive = valid_archive_entries.except('solectrus-influxdb-backup-2026-05-07.tar.gz')
      uploaded = build_upload('solectrus-backup-20260507-101234.tar', tar_archive(archive))

      expect { described_class.start(uploaded) }
        .to raise_error(BackupUploader::Error, I18n.t('backups.uploader.errors.missing_influx'))
    end

    it 'rejects an archive without helios/config.yaml' do
      archive = valid_archive_entries.except('helios/config.yaml')
      uploaded = build_upload('solectrus-backup-20260507-101234.tar', tar_archive(archive))

      expect { described_class.start(uploaded) }
        .to raise_error(BackupUploader::Error, I18n.t('backups.uploader.errors.missing_config'))
    end

    it 'rejects an upload while a backup is running' do
      allow(BackupRunner).to receive(:in_progress).and_return(double(filename: 'foo'))
      uploaded = build_upload('solectrus-backup-20260507-101234.tar', valid_archive)

      expect { described_class.start(uploaded) }
        .to raise_error(BackupUploader::Error, I18n.t('backups.uploader.errors.backup_in_progress'))
    end

    it 'rejects an upload while a restore is running' do
      allow(RestoreRunner).to receive(:in_progress).and_return(double(filename: 'foo'))
      uploaded = build_upload('solectrus-backup-20260507-101234.tar', valid_archive)

      expect { described_class.start(uploaded) }
        .to raise_error(BackupUploader::Error, I18n.t('backups.uploader.errors.restore_in_progress'))
    end

    it 'rejects an upload when the destination is external' do
      allow(BackupRepository).to receive(:remote?).and_return(true)
      uploaded = build_upload('solectrus-backup-20260507-101234.tar', valid_archive)

      expect { described_class.start(uploaded) }
        .to raise_error(BackupUploader::Error, I18n.t('backups.uploader.errors.remote_destination'))
    end

    it 'rejects an upload when the destination is S3' do
      with_config_yaml('backup' => { 'destination' => 's3', 'aws_bucket' => 'foo',
                                     'aws_access_key_id' => 'k', 'aws_secret_access_key' => 's', 'aws_region' => 'eu' })
      uploaded = build_upload('solectrus-backup-20260507-101234.tar', valid_archive)

      expect { described_class.start(uploaded) }
        .to raise_error(BackupUploader::Error, I18n.t('backups.uploader.errors.remote_destination'))
    end

    it 'refuses to overwrite an existing backup' do
      FileUtils.mkdir_p(backups_dir)
      File.binwrite(File.join(backups_dir, 'solectrus-backup-20260507-101234.tar'), 'pre-existing')
      uploaded = build_upload('solectrus-backup-20260507-101234.tar', valid_archive)

      expect { described_class.start(uploaded) }
        .to raise_error(BackupUploader::Error, I18n.t('backups.uploader.errors.already_exists'))
    end

    it 'prunes old backups before writing the new one' do
      now = Time.zone.now
      4.times do |i|
        filename = "solectrus-backup-20260501-11000#{i}.tar"
        FileUtils.mkdir_p(backups_dir)
        File.binwrite(File.join(backups_dir, filename), 'old')
        File.utime((now - (4 - i).hours).to_i, (now - (4 - i).hours).to_i, File.join(backups_dir, filename))
      end

      uploaded = build_upload('solectrus-backup-20260507-101234.tar', valid_archive)
      described_class.start(uploaded)

      filenames = Dir.children(backups_dir).grep(BackupRepository::FILENAME_PATTERN)
      expect(filenames.size).to eq(BackupRepository::MAX_BACKUPS)
      expect(filenames).to include('solectrus-backup-20260507-101234.tar')
    end

    it 'clears a stale error.txt' do
      FileUtils.mkdir_p(backups_dir)
      File.write(File.join(backups_dir, 'error.txt'), 'previous failure')
      uploaded = build_upload('solectrus-backup-20260507-101234.tar', valid_archive)

      described_class.start(uploaded)

      expect(File).not_to exist(File.join(backups_dir, 'error.txt'))
    end
  end

  def valid_archive
    tar_archive(valid_archive_entries)
  end

  def valid_archive_entries
    {
      'solectrus-postgresql-backup-2026-05-07.sql.gz' => 'p' * 64,
      'solectrus-influxdb-backup-2026-05-07.tar.gz' => 'i' * 128,
      'helios/config.yaml' => "system:\n  admin_password: secret\n",
    }
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

  def build_upload(filename, content)
    tempfile = Tempfile.new(['upload', '.tar']).tap do |f|
      f.binmode
      f.write(content)
      f.flush
      f.rewind
    end
    Rack::Test::UploadedFile.new(tempfile.path, 'application/x-tar', true, original_filename: filename)
  end
end
