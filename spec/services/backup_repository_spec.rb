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
    it 'returns Backup entries for each recorded backup, newest first' do
      record_backup('solectrus-backup-20260508-110000.tar')
      record_backup('solectrus-backup-20260508-120000.tar')

      filenames = described_class.all.map(&:filename)
      expect(filenames).to eq([
                                'solectrus-backup-20260508-120000.tar',
                                'solectrus-backup-20260508-110000.tar',
                              ])
    end

    it 'reads the file list from the archive' do
      record_backup(
        'solectrus-backup-20260508-110000.tar',
        archive: { 'helios/config.yaml' => 'system: {}' },
      )

      backup = described_class.all.first # rubocop:disable Rails/RedundantActiveRecordAllMethod
      expect(backup.files.pluck('name')).to contain_exactly('helios/config.yaml')
    end

    it 'exposes PostgreSQL and InfluxDB sizes from the archive' do
      record_backup(
        'solectrus-backup-20260508-110000.tar',
        archive: {
          'solectrus-postgresql-backup-2026-05-08.sql.gz' => 'p' * 100,
          'solectrus-influxdb-backup-2026-05-08/data.tar.gz' => 'i' * 200,
          'helios/config.yaml' => 'system: {}',
        },
      )

      backup = described_class.all.first # rubocop:disable Rails/RedundantActiveRecordAllMethod
      expect(backup.postgresql_bytes).to eq(100)
      expect(backup.influxdb_bytes).to eq(200)
    end

    it 'collapses many influx shard entries into a single aggregate row' do
      # `influx backup` writes one tarball per shard, so a multi-year database
      # produces hundreds of entries. `backups.files` must stay bounded — the
      # UI only ever surfaces three aggregates (config, postgres, influx).
      record_backup(
        'solectrus-backup-20260508-110000.tar',
        archive: {
          'helios/config.yaml' => 'system: {}',
          'solectrus-postgresql-backup-2026-05-08.sql.gz' => 'p' * 100,
          'solectrus-influxdb-backup-2026-05-08/20260508T100000Z.manifest' => 'm' * 50,
          'solectrus-influxdb-backup-2026-05-08/20260508T100000Z.bolt.gz' => 'b' * 30,
          'solectrus-influxdb-backup-2026-05-08/20260508T100000Z.sqlite.gz' => 's' * 20,
          'solectrus-influxdb-backup-2026-05-08/20260508T100000Z.1.tar.gz' => 'x' * 40,
          'solectrus-influxdb-backup-2026-05-08/20260508T100000Z.2.tar.gz' => 'y' * 60,
        },
      )

      backup = described_class.all.first # rubocop:disable Rails/RedundantActiveRecordAllMethod
      expect(backup.files).to contain_exactly(
        { 'name' => 'helios/config.yaml', 'bytes' => 10 },
        { 'name' => 'solectrus-postgresql-backup-2026-05-08.sql.gz', 'bytes' => 100 },
        { 'name' => 'solectrus-influxdb-backup-2026-05-08', 'bytes' => 200 },
      )
      expect(backup.influxdb_bytes).to eq(200)
    end

    it 'returns created_at in the active Time.zone' do
      Time.use_zone('Europe/Berlin') do
        # The filename's embedded timestamp is the backup's `created_at` and is
        # produced with Time.zone, so a 07:40 Berlin filename must surface as
        # 07:40 CEST regardless of how AR stores the underlying datetime.
        record_backup('solectrus-backup-20260701-074000.tar')

        backup = described_class.all.first # rubocop:disable Rails/RedundantActiveRecordAllMethod
        expect(backup.created_at.zone).to eq('CEST')
        expect(backup.created_at.strftime('%H:%M')).to eq('07:40')
      end
    end

    it 'never auto-imports tars dropped onto the filesystem out-of-band' do
      write_tar('solectrus-backup-20260508-110000.tar')
      File.write(File.join(backups_dir, 'solectrus-backup-20260508-120000.tar.part'), 'in-progress')
      File.write(File.join(backups_dir, 'README.txt'), 'hello')

      expect(described_class.all).to be_empty
    end
  end

  describe '.find!' do
    it 'returns a Backup for an existing recorded filename' do
      record_backup('solectrus-backup-20260508-110000.tar')

      backup = described_class.find!('solectrus-backup-20260508-110000.tar')
      expect(backup.filename).to eq('solectrus-backup-20260508-110000.tar')
    end

    it 'raises NotFound when no row exists for the filename' do
      expect do
        described_class.find!('solectrus-backup-20260508-110000.tar')
      end.to raise_error(described_class::NotFound)
    end

    it 'rejects filenames not matching the pattern' do
      expect { described_class.find!('../etc/passwd') }.to raise_error(described_class::NotFound)
    end
  end

  describe '.destroy!' do
    it 'removes the archive and the row' do
      filename = 'solectrus-backup-20260508-110000.tar'
      record_backup(filename)

      described_class.destroy!(filename)

      expect(File).not_to exist(File.join(backups_dir, filename))
      expect(Backup.where(filename: filename)).not_to exist
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

  describe '.created_at_from' do
    it 'parses the filename timestamp using the configured system timezone, not Time.zone' do
      with_config_yaml('system' => { 'timezone' => 'Europe/Berlin' })

      # Background workers (S3 uploader thread, etc.) run with Rails' default
      # Time.zone = UTC. The filename was produced in Berlin local time, so
      # parsing it must use the system zone regardless of caller thread.
      result = Time.use_zone('UTC') do
        described_class.created_at_from('solectrus-backup-20260525-222658.tar')
      end

      expected = ActiveSupport::TimeZone['Europe/Berlin'].local(2026, 5, 25, 22, 26, 58)
      expect(result).to eq(expected)
    end

    it 'returns nil for an unparseable filename' do
      expect(described_class.created_at_from('not-a-backup.txt')).to be_nil
    end
  end

  describe '.prune!' do
    it 'keeps only the four most recent backups (MAX_BACKUPS - 1)' do
      6.times do |i|
        record_backup("solectrus-backup-20260508-11000#{i}.tar")
      end

      described_class.prune!

      expect(described_class.all.map(&:filename)).to eq(%w[
                                                          solectrus-backup-20260508-110005.tar
                                                          solectrus-backup-20260508-110004.tar
                                                          solectrus-backup-20260508-110003.tar
                                                          solectrus-backup-20260508-110002.tar
                                                        ])
    end
  end

  describe 'image versions' do
    it 'reads the InfluxDB and PostgreSQL images from the archived config.yaml' do
      record_backup(
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
      record_backup('solectrus-backup-20260508-110000.tar')

      backup = described_class.find!('solectrus-backup-20260508-110000.tar')
      expect(backup.influxdb_image).to be_nil
      expect(backup.postgresql_image).to be_nil
    end
  end

  describe '.error_message' do
    it 'returns nil when no error was recorded' do
      expect(described_class.error_message).to be_nil
    end

    it 'returns the message captured for the backup runner' do
      RunnerLog.record_error!(:backup, 'Disk full')

      expect(described_class.error_message).to eq('Disk full')
    end

    it 'returns the message captured for the restore runner when asked' do
      RunnerLog.record_error!(:restore, 'Restore aborted')

      expect(described_class.error_message(RestoreRunner::ERROR_FILENAME)).to eq('Restore aborted')
    end
  end

  describe '.clear_error!' do
    it 'removes error.txt and clears the RunnerLog row' do
      RunnerLog.record_error!(:backup, 'oops')
      runners_dir = File.join(data_path, 'helios', 'runners')
      FileUtils.mkdir_p(runners_dir)
      path = File.join(runners_dir, 'error.txt')
      File.write(path, 'oops')

      described_class.clear_error!

      expect(File).not_to exist(path)
      expect(described_class.error_message).to be_nil
    end

    it 'is a no-op when no error exists' do
      expect { described_class.clear_error! }.not_to raise_error
    end
  end

  describe 'destination switching' do
    it 'preserves Backup rows when the destination changes' do
      record_backup('solectrus-backup-20260508-110000.tar')

      switch_destination('external', external_path: '/mnt/x')

      expect(described_class.all).to be_empty
      expect(Backup.where(destination: 'local').count).to eq(1)
    end

    it 'reveals the local list again when the destination is switched back' do
      record_backup('solectrus-backup-20260508-110000.tar')
      switch_destination('external', external_path: '/mnt/x')
      expect(described_class.all).to be_empty

      switch_destination('local')
      expect(described_class.all.map(&:filename)).to contain_exactly('solectrus-backup-20260508-110000.tar')
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

  describe '.s3?, .remote?' do
    it 'classifies local as neither s3 nor remote' do
      with_config_yaml('backup' => { 'destination' => 'local' })
      expect([described_class.s3?, described_class.remote?]).to eq([false, false])
    end

    it 'flags external as remote but not s3' do
      with_config_yaml('backup' => { 'destination' => 'external', 'external_path' => '/mnt/x' })
      expect([described_class.s3?, described_class.remote?]).to eq([false, true])
    end

    it 'flags s3 as both' do
      with_config_yaml('backup' => { 'destination' => 's3', 'aws_bucket' => 'b',
                                     'aws_access_key_id' => 'k', 'aws_secret_access_key' => 's', 'aws_region' => 'eu' })
      expect([described_class.s3?, described_class.remote?]).to eq([true, true])
    end
  end

  # Drops a tar on disk *and* records the matching Backup row via the
  # production code path, so the spec exercises the same insert that
  # detect_completion! triggers in production.
  def record_backup(filename, archive: { 'helios/config.yaml' => 'system: {}' })
    write_tar(filename, archive: archive)
    described_class.record_backup!(filename)
  end

  def write_tar(filename, archive: { 'helios/config.yaml' => 'system: {}' })
    FileUtils.mkdir_p(backups_dir)
    File.binwrite(File.join(backups_dir, filename), tar_archive(archive))
  end

  # Writes a minimal config.yaml at the existing data_path and clears the
  # Configuration cache so the new destination is observable immediately —
  # the alternative (`with_config_yaml`) swaps data_path to a fresh tmpdir,
  # which would orphan the recorded backups under the old path.
  def switch_destination(destination, **fields)
    FileUtils.mkdir_p(File.join(data_path, 'helios'))
    File.write(Configuration.path,
               YAML.dump('backup' => { 'destination' => destination, **fields.transform_keys(&:to_s) }))
    Current.reset
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
