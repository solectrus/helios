# Integration coverage for the External backup adapter against a real local
# directory and the real, pinned `docker:cli` image.
#
# This is the guard for the docker:cli image pin (BackupRunner::IMAGE, which
# External::IMAGE references): the adapter shells `stat`, `tar -tvf`,
# `tar -xOf` and `rm` inside the sidecar and parses their output. A version
# bump that changed busybox's behaviour or output format would break here.
#
# Tagged :integration by its spec/integration/ location — runs on CI and
# locally only with `--tag integration`. Skipped when Docker is absent.
RSpec.describe BackupRepository::External do
  let(:external_path) { Dir.mktmpdir('helios-itest-external') }

  before do
    skip_without_docker
    with_config_yaml('backup' => { 'destination' => 'external', 'external_path' => external_path })
    Current.reset
  end

  after { FileUtils.rm_rf(external_path) }

  describe '.all' do
    it 'returns an empty list for an empty mount' do
      expect(described_class.all).to be_empty
    end

    it 'returns the recorded backups' do
      write_and_record(filename)

      backups = described_class.all
      aggregate_failures do
        expect(backups.map(&:filename)).to eq([filename])
        expect(backups.first.bytes).to eq(File.size(File.join(external_path, filename)))
        expect(backups.first.files.pluck('name')).to include('helios/config.yaml')
        expect(backups.first.influxdb_image).to eq('influxdb:2-alpine')
        expect(backups.first.postgresql_image).to eq('postgres:18-alpine')
      end
    end

    it 'orders backups newest first' do
      older = 'solectrus-backup-20260508-100000.tar'
      newer = 'solectrus-backup-20260508-140000.tar'
      write_and_record(older)
      write_and_record(newer)

      expect(described_class.all.map(&:filename)).to eq([newer, older])
    end
  end

  describe '.record_backup!' do
    it 'reads tar metadata via a single docker:cli sidecar (real `stat` + `tar -tvf` + `tar -xOf`)' do
      write_tar(filename)

      described_class.record_backup!(filename)

      backup = described_class.find!(filename)
      expect(backup.bytes).to eq(File.size(File.join(external_path, filename)))
      expect(backup.influxdb_image).to eq('influxdb:2-alpine')
      expect(backup.postgresql_image).to eq('postgres:18-alpine')
    end
  end

  describe '.find!' do
    it 'returns the stored backup' do
      write_and_record(filename)

      expect(described_class.find!(filename).filename).to eq(filename)
    end

    it 'raises NotFound when the backup is absent' do
      expect { described_class.find!(filename) }.to raise_error(BackupRepository::NotFound)
    end
  end

  describe '.download' do
    it 'streams the stored tar back byte-for-byte' do
      write_and_record(filename)

      streamed = +''
      described_class.download(filename) { |chunk| streamed << chunk }
      expect(streamed.b).to eq(File.binread(File.join(external_path, filename)))
    end
  end

  describe '.destroy!' do
    it 'removes the tar from the mount and the row from the DB' do
      write_and_record(filename)

      described_class.destroy!(filename)

      aggregate_failures do
        expect(File).not_to exist(File.join(external_path, filename))
        expect(described_class.all).to be_empty
      end
    end
  end

  describe '.prune!' do
    it 'deletes all but the newest backups' do
      write_and_record('solectrus-backup-20260508-100000.tar')
      write_and_record('solectrus-backup-20260508-120000.tar')
      write_and_record('solectrus-backup-20260508-140000.tar')

      described_class.prune!(keep: 1)

      expect(Dir.children(external_path)).to contain_exactly('solectrus-backup-20260508-140000.tar')
    end
  end

  describe 'error file IO via real sidecar' do
    it 'reads error.txt from the mount via `cat` sidecar' do
      File.write(File.join(external_path, 'error.txt'), "Disk full\n")

      expect(described_class.send(:read_error_file)).to eq('Disk full')
    end

    it 'removes error.txt via `rm` sidecar' do
      File.write(File.join(external_path, 'error.txt'), "Disk full\n")

      described_class.send(:remove_error_file!)

      expect(File).not_to exist(File.join(external_path, 'error.txt'))
    end
  end

  # --- helpers ---

  def filename
    'solectrus-backup-20260508-120000.tar'
  end

  # Writes a valid HELIOS backup tar to the external mount AND inserts the
  # matching Backup row via the production path, mirroring what
  # detect_completion! does after a real run.
  def write_and_record(name)
    write_tar(name)
    described_class.record_backup!(name)
  end

  # Writes a valid HELIOS backup tar to the external mount. Entries are
  # `./`-prefixed exactly as backup.sh produces them (`tar -cf -C dir .`),
  # so the adapter's `tar -xOf ./helios/config.yaml` member match is real.
  def write_tar(name)
    path = File.join(external_path, name)
    File.binwrite(path, tar_archive(
                          './helios/config.yaml' => { 'influxdb' => { 'image' => 'influxdb:2-alpine' },
                                                      'postgresql' => { 'image' => 'postgres:18-alpine' } }.to_yaml,
                          './solectrus-postgresql-backup-2026-05-08.sql.gz' => 'postgres dump',
                          './solectrus-influxdb-backup-2026-05-08.tar.gz' => 'influx export',
                        ))
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
