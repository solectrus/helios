RSpec.describe BackupRepository::External do
  let(:external_path) { '/mnt/nas/solectrus-backups' }

  before do
    with_config_yaml('backup' => { 'destination' => 'external', 'external_path' => external_path })
    # Replace the test env's null_store so detect_completion! can persist
    # the "backup was in progress" marker between calls within a spec.
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    allow(BackupRunner).to receive(:in_progress).and_return(nil)
    allow(RestoreRunner).to receive(:in_progress).and_return(nil)
  end

  describe '.host_directory' do
    it 'returns the configured external_path' do
      expect(described_class.host_directory).to eq(external_path)
    end

    it 'returns nil when no external_path is configured' do
      with_config_yaml('backup' => { 'destination' => 'external' })
      expect(described_class.host_directory).to be_nil
    end
  end

  describe '.directory' do
    it 'is nil because the external mount is never bind-mounted into HELIOS' do
      expect(described_class.directory).to be_nil
    end
  end

  describe '.all' do
    it 'returns an empty list when host_directory is missing' do
      with_config_yaml('backup' => { 'destination' => 'external' })
      expect(described_class.all).to be_empty
    end

    it 'returns DB rows scoped to the configured external_path, newest first, without hitting docker' do
      create_row('solectrus-backup-20260508-100000.tar')
      create_row('solectrus-backup-20260508-120000.tar')
      allow(Open3).to receive(:capture2)
      allow(Open3).to receive(:capture2e)

      filenames = described_class.all.map(&:filename)

      expect(filenames).to eq(%w[solectrus-backup-20260508-120000.tar solectrus-backup-20260508-100000.tar])
      expect(Open3).not_to have_received(:capture2)
      expect(Open3).not_to have_received(:capture2e)
    end

    it 'does not surface rows recorded for a different external_path' do
      create_row('solectrus-backup-20260508-100000.tar', external_path: '/some/other/mount')

      expect(described_class.all).to be_empty
    end
  end

  describe '.find!' do
    it 'raises NotFound for an invalid filename' do
      expect { described_class.find!('garbage') }.to raise_error(BackupRepository::NotFound)
    end

    it 'raises NotFound when no row exists for the filename' do
      expect { described_class.find!('solectrus-backup-20260508-100000.tar') }
        .to raise_error(BackupRepository::NotFound)
    end

    it 'returns the Backup row when the filename matches' do
      create_row('solectrus-backup-20260508-100000.tar')

      backup = described_class.find!('solectrus-backup-20260508-100000.tar')
      expect(backup.filename).to eq('solectrus-backup-20260508-100000.tar')
    end
  end

  describe '.destroy!' do
    it 'raises NotFound when no row exists' do
      expect { described_class.destroy!('solectrus-backup-20260508-100000.tar') }
        .to raise_error(BackupRepository::NotFound)
    end

    it 'runs rm via sidecar and removes the DB row' do
      create_row('solectrus-backup-20260508-100000.tar')
      stub_capture2e(success: true)

      described_class.destroy!('solectrus-backup-20260508-100000.tar')

      expect(Open3).to have_received(:capture2e).with(
        'docker', 'run', '--rm',
        '--mount', "type=bind,source=#{external_path},target=/data",
        '--entrypoint', 'rm', described_class::IMAGE,
        '-f', '/data/solectrus-backup-20260508-100000.tar'
      )
      expect(Backup.where(filename: 'solectrus-backup-20260508-100000.tar')).not_to exist
    end

    it 'raises BackupRepository::Error and leaves the DB row in place when the sidecar fails' do
      create_row('solectrus-backup-20260508-100000.tar')
      allow(Open3).to receive(:capture2e).and_return(
        ['rm: permission denied', instance_double(Process::Status, success?: false, exitstatus: 1)],
      )

      expect { described_class.destroy!('solectrus-backup-20260508-100000.tar') }
        .to raise_error(BackupRepository::Error, /permission denied/)
      expect(Backup.where(filename: 'solectrus-backup-20260508-100000.tar')).to exist
    end
  end

  describe '.error_message' do
    it 'reads the backup runner error from RunnerLog' do
      RunnerLog.record_error!(:backup, 'PostgreSQL dump failed')
      expect(BackupRepository.error_message).to eq('PostgreSQL dump failed')
    end

    it 'reads the restore runner error from RunnerLog' do
      RunnerLog.record_error!(:restore, 'Restore aborted')
      expect(BackupRepository.error_message(RestoreRunner::ERROR_FILENAME)).to eq('Restore aborted')
    end
  end

  describe '.record_backup!' do
    it 'reads metadata via a single sidecar invocation and inserts a Backup row' do # rubocop:disable RSpec/ExampleLength
      stub_capture2(success: true, output: <<~OUT)
        SIZE|1024
        ENTRY|2816|./solectrus-postgresql-backup-2026-05-08.sql.gz
        ENTRY|4096|./solectrus-influxdb-backup-2026-05-08/20260508T100000Z.1.tar.gz
        ENTRY|2048|./solectrus-influxdb-backup-2026-05-08/20260508T100000Z.bolt.gz
        ENTRY|1024|./solectrus-influxdb-backup-2026-05-08/20260508T100000Z.manifest
        ENTRY|154|./helios/config.yaml
        CONFIG_BEGIN
        postgresql:
          image: postgres:18
        influxdb:
          image: influxdb:2.9-alpine
        CONFIG_END
      OUT

      described_class.record_backup!('solectrus-backup-20260508-100000.tar')
      backup = described_class.find!('solectrus-backup-20260508-100000.tar')

      expect(backup).to have_attributes(
        bytes: 1024,
        influxdb_image: 'influxdb:2.9-alpine',
        postgresql_image: 'postgres:18',
      )
      # The three per-shard influx entries collapse into a single aggregate row
      # under the directory prefix, so `files` stays at three entries regardless
      # of how many shards `influx backup` produced.
      expect(backup.files).to contain_exactly(
        { 'name' => 'helios/config.yaml', 'bytes' => 154 },
        { 'name' => 'solectrus-postgresql-backup-2026-05-08.sql.gz', 'bytes' => 2816 },
        { 'name' => 'solectrus-influxdb-backup-2026-05-08', 'bytes' => 7168 },
      )
    end

    it 'records the destination coordinates so a destination change hides the row' do
      stub_capture2(success: true, output: "SIZE|1024\n")

      described_class.record_backup!('solectrus-backup-20260508-100000.tar')

      row = Backup.find_by(filename: 'solectrus-backup-20260508-100000.tar')
      expect(row.destination).to eq('external')
      expect(row.external_path).to eq(external_path)
    end

    it 'rejects filenames that do not match the canonical pattern' do
      expect { described_class.record_backup!('garbage.tar') }.to raise_error(BackupRepository::NotFound)
    end

    it 'is a no-op when the sidecar fails (transient docker outage)' do
      stub_capture2(success: false, output: '')

      expect { described_class.record_backup!('solectrus-backup-20260508-100000.tar') }.not_to raise_error
      expect(Backup.count).to eq(0)
    end
  end

  describe '.detect_completion!' do
    let(:filename) { 'solectrus-backup-20260508-100000.tar' }

    it 'records the current in-progress filename so the next visit can detect completion' do
      described_class.mark_pending!(filename)
      allow(BackupRunner).to receive(:in_progress)
        .and_return(BackupRepository::InProgress.new(started_at: Time.zone.now, filename: filename))

      described_class.detect_completion!

      expect(Rails.cache.read(described_class.send(:in_progress_cache_key))).to eq(filename)
    end

    # The scheduler calls this every 30 s; with no pending marker and no cached
    # observation there is nothing to detect, so it must not shell out to
    # `docker inspect` via the in-progress probes.
    it 'skips the docker probes when neither a marker nor a cached run exists' do
      described_class.detect_completion!

      expect(BackupRunner).not_to have_received(:in_progress)
      expect(RestoreRunner).not_to have_received(:in_progress)
    end

    it 'inserts the Backup row for the expected filename when the run finishes successfully' do
      described_class.mark_pending!(filename)
      # No error files on disk → read_error_file returns nil.
      # The single sidecar call left is fetch_metadata for the new tar.
      stub_capture2(success: true, output: metadata_output)

      described_class.detect_completion!

      expect(Backup.find_by(filename: filename)).to be_present
      expect(File).not_to exist(described_class.send(:pending_marker_path))
    end

    it 'captures error.txt into RunnerLog when the run failed' do
      described_class.mark_pending!(filename)
      write_runtime_error(BackupRepository::ERROR_FILENAME, 'Disk full')

      described_class.detect_completion!

      expect(RunnerLog.message_for(:backup)).to eq('Disk full')
      expect(Backup.count).to eq(0)
      expect(File).not_to exist(runtime_error_path(BackupRepository::ERROR_FILENAME))
    end

    it 'records a generic "incomplete" message once the retry budget is exhausted' do
      described_class.mark_pending!(filename)
      stub_capture2(success: true, output: '') # fetch_metadata never yields bytes

      BackupRepository::Tracking::RECORDING_MAX_ATTEMPTS.times { described_class.detect_completion! }

      expect(RunnerLog.message_for(:backup)).to eq(I18n.t('backups.runner.errors.incomplete'))
      expect(File).not_to exist(described_class.send(:pending_marker_path))
    end

    it 'does nothing in the steady state' do
      described_class.detect_completion!

      expect(Backup.count).to eq(0)
      expect(RunnerLog.count).to eq(0)
    end

    # A transient failure to read the freshly written tar (NAS/docker hiccup)
    # must not lose the backup: the marker is kept and the next tick retries.
    it 'keeps the marker and records the backup on a later retry' do
      described_class.mark_pending!(filename)
      sidecar_responses(['', success_status], [metadata_output, success_status])

      described_class.detect_completion! # first read fails → kept for retry
      expect(Backup.count).to eq(0)
      expect(RunnerLog.message_for(:backup)).to be_nil
      expect(File).to exist(described_class.send(:pending_marker_path))

      described_class.detect_completion! # retry succeeds
      expect(Backup.find_by(filename:)).to be_present
      expect(File).not_to exist(described_class.send(:pending_marker_path))
    end
  end

  describe '.mark_pending!' do
    it 'creates a marker file under data_path/helios' do
      described_class.mark_pending!

      expect(File).to exist(described_class.send(:pending_marker_path))
    end

    it 'is a no-op when no external_path is configured' do
      with_config_yaml('backup' => { 'destination' => 'external' })

      described_class.mark_pending!

      expect(File).not_to exist(described_class.send(:pending_marker_path))
    end
  end

  describe '.read_archive_for' do
    it 'returns EMPTY_ARCHIVE when host_directory is missing' do
      with_config_yaml('backup' => { 'destination' => 'external' })
      expect(described_class.read_archive_for('whatever.tar')).to eq(BackupRepository::EMPTY_ARCHIVE)
    end
  end

  describe '.download' do
    let(:filename) { 'solectrus-backup-20260508-100000.tar' }

    it 'raises NotFound for an invalid filename' do
      expect { described_class.download('garbage') { nil } }.to raise_error(BackupRepository::NotFound)
    end

    it 'raises NotFound when host_directory is not configured' do
      with_config_yaml('backup' => { 'destination' => 'external' })
      expect { described_class.download(filename) { nil } }.to raise_error(BackupRepository::NotFound)
    end

    it 'raises NotFound when the filename has no row in the DB' do
      expect { described_class.download(filename) { nil } }.to raise_error(BackupRepository::NotFound)
    end

    it 'streams the sidecar stdout to the block in chunks' do
      create_row(filename)
      stub_popen2(stdout: 'tar-bytes', success: true)

      chunks = []
      described_class.download(filename) { |chunk| chunks << chunk }

      expect(chunks.join).to eq('tar-bytes')
    end

    it 'passes the canonical /data path, rebuilt from the filename, to the sidecar' do
      create_row(filename)
      stub_popen2(stdout: 'tar-bytes', success: true)

      described_class.download(filename) { nil }

      expect(Open3).to have_received(:popen2) do |*args|
        expect(args).to include('cat', "/data/#{filename}")
      end
    end

    it 'raises BackupRepository::Error when the sidecar exits non-zero' do
      create_row(filename)
      stub_popen2(stdout: '', success: false, exitstatus: 1)

      expect { described_class.download(filename) { nil } }.to raise_error(BackupRepository::Error, /status 1/)
    end
  end

  def runtime_error_path(filename)
    File.join(Rails.configuration.data_path, 'helios', 'runners', filename)
  end

  def write_runtime_error(filename, content)
    path = runtime_error_path(filename)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  def create_row(filename, external_path: self.external_path)
    Backup.create!(
      filename: filename,
      bytes: 1024,
      created_at: BackupRepository.created_at_from(filename) || Time.current,
      destination: 'external',
      external_path: external_path,
      files: [{ 'name' => 'helios/config.yaml', 'bytes' => 10 }],
    )
  end

  def metadata_output
    <<~OUT
      SIZE|1024
      ENTRY|2816|./solectrus-postgresql-backup-2026-05-08.sql.gz
      ENTRY|7168|./solectrus-influxdb-backup-2026-05-08.tar.gz
      ENTRY|154|./helios/config.yaml
      CONFIG_BEGIN
      postgresql:
        image: postgres:18
      CONFIG_END
    OUT
  end

  def stub_capture2(success:, output:)
    allow(Open3).to receive(:capture2).and_return([output, instance_double(Process::Status, success?: success)])
  end

  def stub_capture2e(success:)
    allow(Open3).to receive(:capture2e).and_return(['', instance_double(Process::Status, success?: success)])
  end

  def sidecar_responses(*responses)
    allow(Open3).to receive(:capture2).and_return(*responses)
  end

  def success_status
    instance_double(Process::Status, success?: true)
  end

  def stub_popen2(stdout:, success:, exitstatus: 0)
    status = instance_double(Process::Status, success?: success, exitstatus: exitstatus)
    wait_thr = instance_double(Thread, value: status)
    allow(Open3).to receive(:popen2).and_yield(StringIO.new, StringIO.new(+stdout), wait_thr)
  end
end
