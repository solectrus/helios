RSpec.describe BackupRepository::External do
  let(:external_path) { '/mnt/nas/solectrus-backups' }

  before do
    with_config_yaml('backup' => { 'destination' => 'external', 'external_path' => external_path })
    # Replace the test env's null_store so detect_completion! can persist
    # the "backup was in progress" marker between calls within a spec.
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    allow(BackupRunner).to receive(:in_progress).and_return(nil)
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
    it 'returns an empty array when host_directory is missing' do
      with_config_yaml('backup' => { 'destination' => 'external' })
      expect(described_class.all).to eq([])
    end

    it 'returns the cached backups, newest first, without hitting docker' do
      write_index(
        'external_path' => external_path,
        'backups' => [
          backup_entry('solectrus-backup-20260508-100000.tar', bytes: 1024, mtime: '2026-05-08T10:00:00Z'),
          backup_entry('solectrus-backup-20260508-120000.tar', bytes: 2048, mtime: '2026-05-08T12:00:00Z'),
        ],
      )
      allow(Open3).to receive(:capture2)
      allow(Open3).to receive(:capture2e)

      filenames = described_class.all.map(&:filename)

      expect(filenames).to contain_exactly(
        'solectrus-backup-20260508-100000.tar',
        'solectrus-backup-20260508-120000.tar',
      )
      expect(Open3).not_to have_received(:capture2)
      expect(Open3).not_to have_received(:capture2e)
    end

    it 'rebuilds the index from docker when the cached external_path no longer matches' do
      write_index('external_path' => '/somewhere/else', 'backups' => [])
      stub_capture2(success: true, output: listing_output)
      allow(described_class).to receive(:build_entry) do |meta|
        backup_entry(meta[:filename], bytes: meta[:bytes], mtime: meta[:mtime].iso8601)
      end

      described_class.all

      expect(read_index['external_path']).to eq(external_path)
    end

    it 'rebuilds the index when a cached entry has empty files (a failed earlier read)' do
      write_index('external_path' => external_path,
                  'backups' => [backup_entry('solectrus-backup-20260508-100000.tar', files: [])])
      stub_capture2(success: true, output: listing_output)
      allow(described_class).to receive(:build_entry) do |meta|
        backup_entry(meta[:filename], bytes: meta[:bytes], mtime: meta[:mtime].iso8601)
      end

      described_class.all

      expect(read_index['backups']).to all(include('files' => be_present))
    end
  end

  describe '.find!' do
    it 'raises NotFound for an invalid filename' do
      expect { described_class.find!('garbage') }.to raise_error(BackupRepository::NotFound)
    end

    it 'raises NotFound for a filename that is not in the index' do
      write_index('external_path' => external_path, 'backups' => [])
      expect { described_class.find!('solectrus-backup-20260508-100000.tar') }
        .to raise_error(BackupRepository::NotFound)
    end

    it 'returns the cached Backup when the filename is in the index' do
      write_index(
        'external_path' => external_path,
        'backups' => [backup_entry('solectrus-backup-20260508-100000.tar', bytes: 1024, mtime: '2026-05-08T10:00:00Z')],
      )

      backup = described_class.find!('solectrus-backup-20260508-100000.tar')
      expect(backup.filename).to eq('solectrus-backup-20260508-100000.tar')
      expect(backup.bytes).to eq(1024)
    end
  end

  describe '.destroy!' do
    it 'raises NotFound when the filename is not in the index' do
      write_index('external_path' => external_path, 'backups' => [])
      expect { described_class.destroy!('solectrus-backup-20260508-100000.tar') }
        .to raise_error(BackupRepository::NotFound)
    end

    it 'runs rm via sidecar and removes the entry from the index' do
      write_index(
        'external_path' => external_path,
        'backups' => [backup_entry('solectrus-backup-20260508-100000.tar')],
      )
      stub_capture2e(success: true)

      described_class.destroy!('solectrus-backup-20260508-100000.tar')

      expect(Open3).to have_received(:capture2e).with(
        'docker', 'run', '--rm', '-v', "#{external_path}:/data",
        '--entrypoint', 'rm', described_class::IMAGE,
        '-f', '/data/solectrus-backup-20260508-100000.tar',
        '/data/solectrus-backup-20260508-100000.tar.json'
      )
      expect(read_index['backups']).to be_empty
    end

    it 'raises BackupRepository::Error and leaves the index untouched when the sidecar fails' do
      write_index(
        'external_path' => external_path,
        'backups' => [backup_entry('solectrus-backup-20260508-100000.tar')],
      )
      allow(Open3).to receive(:capture2e).and_return(
        ['rm: permission denied', instance_double(Process::Status, success?: false, exitstatus: 1)],
      )

      expect { described_class.destroy!('solectrus-backup-20260508-100000.tar') }
        .to raise_error(BackupRepository::Error, /permission denied/)

      expect(read_index['backups'].pluck('filename')).to include('solectrus-backup-20260508-100000.tar')
    end
  end

  describe '.error_message' do
    it 'returns the cached error_message for the default filename' do
      write_index('external_path' => external_path, 'backups' => [], 'error_message' => 'PostgreSQL dump failed')
      expect(described_class.error_message).to eq('PostgreSQL dump failed')
    end

    it 'returns the cached restore_error_message for the restore filename' do
      write_index('external_path' => external_path, 'backups' => [],
                  'restore_error_message' => 'Restore aborted')
      expect(described_class.error_message(RestoreRunner::ERROR_FILENAME)).to eq('Restore aborted')
    end

    it 'returns nil from the cache without hitting docker for unknown filenames' do
      allow(Open3).to receive(:capture2)
      write_index('external_path' => external_path, 'backups' => [])

      expect(described_class.error_message('something-else.txt')).to be_nil
      expect(Open3).not_to have_received(:capture2)
    end

    it 'returns nil when the cached error_message is empty' do
      write_index('external_path' => external_path, 'backups' => [], 'error_message' => nil)
      expect(described_class.error_message).to be_nil
    end
  end

  describe '.refresh!' do
    it 'deletes the index when host_directory is missing' do
      write_index('external_path' => '/old', 'backups' => [{ 'filename' => 'x' }])
      with_config_yaml('backup' => { 'destination' => 'external' })

      described_class.refresh!

      expect(BackupRepository::Index.read).to be_nil
    end

    it 'writes a new index from the sidecar listing' do
      stub_capture2(success: true, output: listing_output)
      allow(described_class).to receive(:build_entry) do |meta|
        backup_entry(meta[:filename], bytes: meta[:bytes], mtime: meta[:mtime].iso8601)
      end

      described_class.refresh!

      expect(read_index['external_path']).to eq(external_path)
      expect(read_index['backups'].pluck('filename')).to eq(%w[
                                                              solectrus-backup-20260508-120000.tar
                                                              solectrus-backup-20260508-100000.tar
                                                            ])
    end

    it 'reuses unchanged entries instead of re-reading the archive' do
      write_index(
        'external_path' => external_path,
        'backups' => [
          backup_entry('solectrus-backup-20260508-100000.tar', bytes: 1024, mtime: Time.zone.at(1_715_165_400).iso8601,
                                                               files: [{ 'name' => 'cached-file', 'bytes' => 10 }]),
        ],
      )
      stub_capture2(success: true, output: listing_output)
      allow(described_class).to receive(:build_entry) do |meta|
        backup_entry(meta[:filename], bytes: meta[:bytes], mtime: meta[:mtime].iso8601)
      end

      described_class.refresh!

      expect(described_class).not_to have_received(:build_entry)
        .with(hash_including(filename: 'solectrus-backup-20260508-100000.tar'))
      reused = read_index['backups'].find { |entry| entry['filename'] == 'solectrus-backup-20260508-100000.tar' }
      expect(reused['files']).to eq([{ 'name' => 'cached-file', 'bytes' => 10 }])
    end

    it 'rebuilds a cached entry whose files are empty (a failed earlier metadata read)' do
      write_index(
        'external_path' => external_path,
        'backups' => [
          backup_entry('solectrus-backup-20260508-100000.tar', bytes: 1024,
                                                               mtime: Time.zone.at(1_715_165_400).iso8601,
                                                               files: []),
        ],
      )
      stub_capture2(success: true, output: listing_output)
      allow(described_class).to receive(:build_entry) do |meta|
        backup_entry(meta[:filename], bytes: meta[:bytes], mtime: meta[:mtime].iso8601,
                                      files: [{ 'name' => 'helios/config.yaml', 'bytes' => 99 }])
      end

      described_class.refresh!

      expect(described_class).to have_received(:build_entry)
        .with(hash_including(filename: 'solectrus-backup-20260508-100000.tar'))
      rebuilt = read_index['backups'].find { |entry| entry['filename'] == 'solectrus-backup-20260508-100000.tar' }
      expect(rebuilt['files']).not_to be_empty
    end

    it 'captures backup and restore error files into the index' do
      stub_capture2(success: true, output: <<~OUT)
        ERROR_MESSAGE_BEGIN
        PostgreSQL dump failed
        ERROR_MESSAGE_END
        RESTORE_ERROR_MESSAGE_BEGIN
        Restore aborted
        RESTORE_ERROR_MESSAGE_END
      OUT

      described_class.refresh!

      expect(read_index['error_message']).to eq('PostgreSQL dump failed')
      expect(read_index['restore_error_message']).to eq('Restore aborted')
    end

    it 'leaves error fields nil when neither file is present' do
      stub_capture2(success: true, output: '')

      described_class.refresh!

      expect(read_index['error_message']).to be_nil
      expect(read_index['restore_error_message']).to be_nil
    end

    it 'keeps the existing index when the sidecar fails (a transient docker outage)' do
      write_index('external_path' => external_path,
                  'backups' => [backup_entry('solectrus-backup-20260508-100000.tar')])
      stub_capture2(success: false, output: '')

      described_class.refresh!

      expect(read_index['backups'].pluck('filename')).to eq(['solectrus-backup-20260508-100000.tar'])
    end
  end

  describe '.detect_completion!' do
    it 'records the current in-progress filename so the next visit can detect completion' do
      allow(BackupRunner).to receive(:in_progress)
        .and_return(BackupRepository::InProgress.new(started_at: Time.zone.now, filename: 'foo.tar'))

      described_class.detect_completion!

      expect(Rails.cache.read(described_class.send(:in_progress_cache_key))).to eq('foo.tar')
    end

    it 'refreshes the index when in-progress disappears' do
      Rails.cache.write(described_class.send(:in_progress_cache_key), 'foo.tar', expires_in: 1.hour)
      allow(BackupRunner).to receive(:in_progress).and_return(nil)
      allow(described_class).to receive(:refresh!)

      described_class.detect_completion!

      expect(described_class).to have_received(:refresh!)
      expect(Rails.cache.read(described_class.send(:in_progress_cache_key))).to be_nil
    end

    it 'does nothing in the steady state (no running backup, no completion to detect)' do
      allow(BackupRunner).to receive(:in_progress).and_return(nil)
      allow(described_class).to receive(:refresh!)

      described_class.detect_completion!

      expect(described_class).not_to have_received(:refresh!)
    end

    it 'refreshes when a pending marker exists even without an observed in-progress run' do
      FileUtils.mkdir_p(File.dirname(described_class.send(:pending_marker_path)))
      FileUtils.touch(described_class.send(:pending_marker_path))
      allow(BackupRunner).to receive(:in_progress).and_return(nil)
      allow(described_class).to receive(:refresh!)

      described_class.detect_completion!

      expect(described_class).to have_received(:refresh!)
      expect(File).not_to exist(described_class.send(:pending_marker_path))
    end

    it 'records a failure when a pending backup never appeared and left no error' do
      described_class.mark_pending!('solectrus-backup-20260508-100000.tar')
      allow(BackupRunner).to receive(:in_progress).and_return(nil)
      stub_capture2(success: true, output: '')

      described_class.detect_completion!

      expect(read_index['error_message']).to eq(I18n.t('backups.runner.errors.incomplete'))
    end

    it 'leaves a captured error untouched instead of overwriting it with the generic failure' do
      described_class.mark_pending!('solectrus-backup-20260508-100000.tar')
      allow(BackupRunner).to receive(:in_progress).and_return(nil)
      stub_capture2(success: true, output: "ERROR_MESSAGE_BEGIN\nDisk full\nERROR_MESSAGE_END\n")

      described_class.detect_completion!

      expect(read_index['error_message']).to eq('Disk full')
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

  describe '.build_entry (via fetch_metadata)' do
    let(:meta) { { filename: 'solectrus-backup-20260508-100000.tar', bytes: 1024, mtime: Time.zone.at(1_715_165_400) } }

    it 'extracts file list and config images from one sidecar invocation' do
      stub_capture2(success: true, output: <<~OUT)
        ENTRY|2816|./solectrus-postgresql-backup-2026-05-08.sql.gz
        ENTRY|7168|./solectrus-influxdb-backup-2026-05-08.tar.gz
        ENTRY|154|./helios/config.yaml
        CONFIG_BEGIN
        postgresql:
          image: postgres:18
        influxdb:
          image: influxdb:2.9-alpine
        CONFIG_END
      OUT

      entry = described_class.send(:build_entry, meta)

      expect(entry['files']).to contain_exactly(
        { 'name' => 'solectrus-postgresql-backup-2026-05-08.sql.gz', 'bytes' => 2816 },
        { 'name' => 'solectrus-influxdb-backup-2026-05-08.tar.gz', 'bytes' => 7168 },
        { 'name' => 'helios/config.yaml', 'bytes' => 154 },
      )
      expect(entry['influxdb_image']).to eq('influxdb:2.9-alpine')
      expect(entry['postgresql_image']).to eq('postgres:18')
    end

    it 'leaves image fields nil when helios/config.yaml is missing from the tar' do
      stub_capture2(success: true, output: <<~OUT)
        ENTRY|2816|./solectrus-postgresql-backup-2026-05-08.sql.gz
        CONFIG_BEGIN
        CONFIG_END
      OUT

      entry = described_class.send(:build_entry, meta)

      expect(entry['influxdb_image']).to be_nil
      expect(entry['postgresql_image']).to be_nil
    end

    it 'returns an empty entry when the sidecar fails' do
      stub_capture2(success: false, output: '')

      entry = described_class.send(:build_entry, meta)

      expect(entry['files']).to eq([])
      expect(entry['influxdb_image']).to be_nil
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

    it 'raises NotFound when the filename is not in the index' do
      write_index('external_path' => external_path, 'backups' => [])
      expect { described_class.download(filename) { nil } }.to raise_error(BackupRepository::NotFound)
    end

    it 'streams the sidecar stdout to the block in chunks' do
      write_index('external_path' => external_path, 'backups' => [backup_entry(filename)])
      stub_popen2(stdout: 'tar-bytes', success: true)

      chunks = []
      described_class.download(filename) { |chunk| chunks << chunk }

      expect(chunks.join).to eq('tar-bytes')
    end

    it 'passes the canonical /data path, rebuilt from the filename, to the sidecar' do
      write_index('external_path' => external_path, 'backups' => [backup_entry(filename)])
      stub_popen2(stdout: 'tar-bytes', success: true)

      described_class.download(filename) { nil }

      expect(Open3).to have_received(:popen2) do |*args|
        expect(args).to include('cat', "/data/#{filename}")
      end
    end

    it 'raises BackupRepository::Error when the sidecar exits non-zero' do
      write_index('external_path' => external_path, 'backups' => [backup_entry(filename)])
      stub_popen2(stdout: '', success: false, exitstatus: 1)

      expect { described_class.download(filename) { nil } }.to raise_error(BackupRepository::Error, /status 1/)
    end
  end

  def write_index(data)
    FileUtils.mkdir_p(File.dirname(BackupRepository::Index.path))
    File.write(BackupRepository::Index.path, JSON.pretty_generate({ 'destination' => 'external' }.merge(data)))
  end

  def read_index
    JSON.parse(File.read(BackupRepository::Index.path))
  end

  # `files` defaults to a non-empty list: an entry with empty files counts
  # as a stale cache (see IndexedAdapter#index_complete?), so tests relying
  # on a fresh cache need complete entries.
  def backup_entry(filename, bytes: 1024, mtime: '2026-05-08T10:00:00Z',
                   files: [{ 'name' => 'helios/config.yaml', 'bytes' => 10 }])
    {
      'filename' => filename,
      'bytes' => bytes,
      'mtime' => mtime,
      'files' => files,
      'influxdb_image' => nil,
      'postgresql_image' => nil,
    }
  end

  def listing_output
    <<~OUT
      BACKUP|/data/solectrus-backup-20260508-100000.tar|1024|1715165400
      BACKUP|/data/solectrus-backup-20260508-120000.tar|2048|1715172600
    OUT
  end

  def stub_capture2(success:, output:)
    allow(Open3).to receive(:capture2).and_return([output, instance_double(Process::Status, success?: success)])
  end

  def stub_capture2e(success:)
    allow(Open3).to receive(:capture2e).and_return(['', instance_double(Process::Status, success?: success)])
  end

  def stub_popen2(stdout:, success:, exitstatus: 0)
    status = instance_double(Process::Status, success?: success, exitstatus: exitstatus)
    wait_thr = instance_double(Thread, value: status)
    allow(Open3).to receive(:popen2).and_yield(StringIO.new, StringIO.new(+stdout), wait_thr)
  end
end
