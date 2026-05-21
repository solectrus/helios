require 'rubygems/package'

RSpec.describe BackupRepository::S3 do
  let(:data_path) { Dir.mktmpdir }
  let(:host_data_path) { '/host/data' }
  let(:bucket) { 'my-backups' }

  before do
    allow(Rails.configuration).to receive(:data_path).and_return(data_path)
    allow(Orchestration::Runner).to receive(:host_data_path).and_return(host_data_path)
    FileUtils.mkdir_p(File.join(data_path, 'helios'))

    with_config_yaml('backup' => {
                       'destination' => 's3',
                       'aws_bucket' => bucket,
                       'aws_access_key_id' => 'AKIA',
                       'aws_secret_access_key' => 'secret',
                       'aws_region' => 'eu-central-1',
                       's3_prefix' => 'solectrus/',
                     })

    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    allow(BackupRunner).to receive(:in_progress).and_return(nil)
  end

  after { FileUtils.remove_entry(data_path) }

  describe '.host_directory' do
    it 'returns the host-side staging dir when the destination is fully configured' do
      expect(described_class.host_directory).to eq("#{host_data_path}/helios/backups-staging")
    end

    it 'returns nil when the bucket is missing' do
      with_config_yaml('backup' => { 'destination' => 's3', 'aws_access_key_id' => 'k',
                                     'aws_secret_access_key' => 's', 'aws_region' => 'eu' })
      expect(described_class.host_directory).to be_nil
    end

    it 'returns nil when credentials are missing' do
      with_config_yaml('backup' => { 'destination' => 's3', 'aws_bucket' => bucket, 'aws_region' => 'eu' })
      expect(described_class.host_directory).to be_nil
    end

    it 'returns nil when the region is missing' do
      with_config_yaml('backup' => { 'destination' => 's3', 'aws_bucket' => bucket,
                                     'aws_access_key_id' => 'k', 'aws_secret_access_key' => 's' })
      expect(described_class.host_directory).to be_nil
    end
  end

  describe '.directory' do
    it 'is the container-internal staging path so BackupRunner can mkdir it' do
      expect(described_class.directory).to end_with('/helios/backups-staging')
      expect(described_class.directory).to start_with(Rails.configuration.data_path)
    end
  end

  describe '.s3_uri / .s3_dir_uri' do
    it 'normalizes a non-empty prefix into a single-slash separator' do
      with_config_yaml('backup' => valid_backup.merge('s3_prefix' => '/solectrus//'))
      expect(described_class.s3_uri('foo.tar')).to eq('s3://my-backups/solectrus/foo.tar')
      expect(described_class.s3_dir_uri).to eq('s3://my-backups/solectrus/')
    end

    it 'omits the prefix segment when blank' do
      with_config_yaml('backup' => valid_backup.merge('s3_prefix' => ''))
      expect(described_class.s3_uri('foo.tar')).to eq('s3://my-backups/foo.tar')
      expect(described_class.s3_dir_uri).to eq('s3://my-backups/')
    end
  end

  describe '.all' do
    it 'returns the cached backups, newest first, without hitting docker' do
      write_index(
        'bucket' => bucket, 'prefix' => 'solectrus', 'endpoint_url' => nil,
        'backups' => [
          backup_entry('solectrus-backup-20260508-100000.tar', bytes: 1024, mtime: '2026-05-08T10:00:00Z'),
          backup_entry('solectrus-backup-20260508-120000.tar', bytes: 2048, mtime: '2026-05-08T12:00:00Z'),
        ]
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

    it 'rebuilds the index when the cached bucket no longer matches' do
      write_index('bucket' => 'other-bucket', 'prefix' => 'solectrus', 'endpoint_url' => nil, 'backups' => [])
      stub_list([obj('solectrus/solectrus-backup-20260508-100000.tar', 1024, '2026-05-08T10:00:00+00:00')])
      stub_download({ 'solectrus-backup-20260508-100000.tar' => sample_tar })

      described_class.all

      expect(read_index['bucket']).to eq(bucket)
    end

    it 'rebuilds the index when a cached entry has empty files (a failed earlier read)' do
      write_index(
        'bucket' => bucket, 'prefix' => 'solectrus', 'endpoint_url' => nil,
        'backups' => [backup_entry('solectrus-backup-20260508-100000.tar', files: [])]
      )
      stub_list([obj('solectrus/solectrus-backup-20260508-100000.tar', 1024, '2026-05-08T10:00:00+00:00')])
      stub_download({ 'solectrus-backup-20260508-100000.tar' => sample_tar })

      described_class.all

      expect(read_index['backups']).to all(include('files' => be_present))
    end

    it 'returns an empty list when destination is not configured' do
      with_config_yaml('backup' => { 'destination' => 's3' })
      expect(described_class.all).to eq([])
    end
  end

  describe '.find!' do
    it 'raises NotFound for an invalid filename' do
      expect { described_class.find!('garbage') }.to raise_error(BackupRepository::NotFound)
    end

    it 'raises NotFound when the filename is not in the index' do
      write_index('bucket' => bucket, 'prefix' => 'solectrus', 'endpoint_url' => nil, 'backups' => [])
      expect { described_class.find!('solectrus-backup-20260508-100000.tar') }
        .to raise_error(BackupRepository::NotFound)
    end

    it 'returns the cached Backup when the filename is in the index' do
      write_index(
        'bucket' => bucket, 'prefix' => 'solectrus', 'endpoint_url' => nil,
        'backups' => [backup_entry('solectrus-backup-20260508-100000.tar', bytes: 1024, mtime: '2026-05-08T10:00:00Z')]
      )

      backup = described_class.find!('solectrus-backup-20260508-100000.tar')
      expect(backup.filename).to eq('solectrus-backup-20260508-100000.tar')
      expect(backup.bytes).to eq(1024)
    end
  end

  describe '.destroy!' do
    it 'runs `aws s3 rm` via sidecar and removes the entry from the index' do
      write_index(
        'bucket' => bucket, 'prefix' => 'solectrus', 'endpoint_url' => nil,
        'backups' => [backup_entry('solectrus-backup-20260508-100000.tar')]
      )
      stub_capture2e(success: true)

      described_class.destroy!('solectrus-backup-20260508-100000.tar')

      expect(Open3).to have_received(:capture2e).with(*captured_destroy_args)
      expect(read_index['backups']).to be_empty
    end

    def captured_destroy_args
      [
        'docker', 'run', '--rm',
        '-e', 'AWS_ACCESS_KEY_ID=AKIA',
        '-e', 'AWS_SECRET_ACCESS_KEY=secret',
        '-e', 'AWS_DEFAULT_REGION=eu-central-1',
        '-e', 'AWS_REGION=eu-central-1',
        '--entrypoint', 'sh', described_class::IMAGE,
        '-c', a_string_including('aws s3 rm s3://my-backups/solectrus/solectrus-backup-20260508-100000.tar')
      ]
    end

    it 'raises BackupRepository::Error and leaves the index untouched when the sidecar fails' do
      write_index(
        'bucket' => bucket, 'prefix' => 'solectrus', 'endpoint_url' => nil,
        'backups' => [backup_entry('solectrus-backup-20260508-100000.tar')]
      )
      stub_capture2e(success: false, output: 'AccessDenied')

      expect { described_class.destroy!('solectrus-backup-20260508-100000.tar') }
        .to raise_error(BackupRepository::Error, /AccessDenied/)
      expect(read_index['backups'].size).to eq(1)
    end

    it 'raises NotFound when the filename is not in the index' do
      write_index('bucket' => bucket, 'prefix' => 'solectrus', 'endpoint_url' => nil, 'backups' => [])

      expect { described_class.destroy!('solectrus-backup-20260508-100000.tar') }
        .to raise_error(BackupRepository::NotFound)
    end
  end

  describe '.error_message' do
    it 'returns the cached error_message from the index' do
      write_index('bucket' => bucket, 'prefix' => 'solectrus', 'endpoint_url' => nil,
                  'backups' => [], 'error_message' => 'disk full')

      expect(described_class.error_message).to eq('disk full')
    end

    it 'returns nil when destination is not configured' do
      with_config_yaml('backup' => { 'destination' => 's3' })
      expect(described_class.error_message).to be_nil
    end
  end

  describe '.mark_pending! / .detect_completion!' do
    it 'creates the pending marker only when the destination is ready' do
      described_class.mark_pending!
      expect(File).to exist(described_class.pending_marker_path)
    end

    it 'is a no-op when destination is not ready' do
      with_config_yaml('backup' => { 'destination' => 's3' })
      expect { described_class.mark_pending! }.not_to raise_error
      expect(File).not_to exist(described_class.pending_marker_path)
    end

    it 'refreshes the index and clears the marker once the backup is no longer in progress' do
      FileUtils.mkdir_p(File.dirname(described_class.pending_marker_path))
      FileUtils.touch(described_class.pending_marker_path)
      stub_list([])

      described_class.detect_completion!

      expect(described_class.pending_refresh?).to be(false)
    end

    it 'records a failure when a pending backup never appeared and left no error' do
      described_class.mark_pending!('solectrus-backup-20260508-100000.tar')
      stub_list([])

      described_class.detect_completion!

      expect(read_index['error_message']).to eq(I18n.t('backups.runner.errors.incomplete'))
    end
  end

  describe '.refresh!' do
    it 'lists the bucket and parses backups via a single bulk download' do
      stub_list([
                  obj('solectrus/solectrus-backup-20260508-100000.tar', 1024, '2026-05-08T10:00:00+00:00'),
                  obj('solectrus/solectrus-backup-20260508-120000.tar', 2048, '2026-05-08T12:00:00+00:00'),
                ])
      stub_download(
        'solectrus-backup-20260508-100000.tar' => sample_tar,
        'solectrus-backup-20260508-120000.tar' => sample_tar(influxdb: 'influxdb:2.9-alpine'),
      )

      described_class.refresh!

      index = read_index
      aggregate_failures do
        expect(index['backups'].pluck('filename')).to eq(
          ['solectrus-backup-20260508-120000.tar', 'solectrus-backup-20260508-100000.tar'],
        )
        expect(index['backups'].first['influxdb_image']).to eq('influxdb:2.9-alpine')
        expect(index['backups'].first['files'].pluck('name')).to include('helios/config.yaml')
        expect(index['bucket']).to eq(bucket)
        expect(index['prefix']).to eq('solectrus')
      end
    end

    it 'downloads every wanted object in one `aws s3 cp` sidecar' do
      stub_list([
                  obj('solectrus/solectrus-backup-20260508-100000.tar', 1024, '2026-05-08T10:00:00+00:00'),
                  obj('solectrus/solectrus-backup-20260508-120000.tar', 2048, '2026-05-08T12:00:00+00:00'),
                ])
      stub_download(
        'solectrus-backup-20260508-100000.tar' => sample_tar,
        'solectrus-backup-20260508-120000.tar' => sample_tar,
      )

      described_class.refresh!

      expect(Open3).to have_received(:capture2e).once
    end

    it 'deletes the index when destination is not ready' do
      File.write(BackupRepository::Index.path, '{"bucket":"old"}')
      with_config_yaml('backup' => { 'destination' => 's3' })

      described_class.refresh!

      expect(File).not_to exist(BackupRepository::Index.path)
    end

    it 'reads the error file from the bulk download' do
      stub_list([
                  obj('solectrus/solectrus-backup-20260508-100000.tar', 1024, '2026-05-08T10:00:00+00:00'),
                  obj('solectrus/error.txt', 10, '2026-05-08T13:00:00+00:00'),
                ])
      stub_download(
        'solectrus-backup-20260508-100000.tar' => sample_tar,
        'error.txt' => "Disk full\n",
      )

      described_class.refresh!

      expect(read_index['error_message']).to eq('Disk full')
    end

    it 'reuses a cached entry and bulk-downloads only the new backup' do
      cached = 'solectrus-backup-20260508-100000.tar'
      fresh = 'solectrus-backup-20260508-120000.tar'
      write_index(
        'bucket' => bucket, 'prefix' => 'solectrus', 'endpoint_url' => nil,
        'backups' => [backup_entry(cached, bytes: 1024, mtime: '2026-05-08T10:00:00Z',
                                           files: [{ 'name' => 'cached-marker', 'bytes' => 1 }])]
      )
      stub_list([
                  obj("solectrus/#{cached}", 1024, '2026-05-08T10:00:00+00:00'),
                  obj("solectrus/#{fresh}", 2048, '2026-05-08T12:00:00+00:00'),
                ])
      stub_download(fresh => sample_tar)

      described_class.refresh!

      backups = read_index['backups'].index_by { |entry| entry['filename'] }
      aggregate_failures do
        # the cached entry is kept verbatim — never re-downloaded or re-parsed
        expect(backups[cached]['files']).to eq([{ 'name' => 'cached-marker', 'bytes' => 1 }])
        # the new backup is parsed from the freshly downloaded tar
        expect(backups[fresh]['files'].pluck('name')).to include('helios/config.yaml')
      end
    end

    it 'keeps the existing index when the listing sidecar fails (a transient outage)' do
      write_index(
        'bucket' => bucket, 'prefix' => 'solectrus', 'endpoint_url' => nil,
        'backups' => [backup_entry('solectrus-backup-20260508-100000.tar')]
      )
      stub_list([], success: false)

      described_class.refresh!

      expect(read_index['backups'].pluck('filename')).to eq(['solectrus-backup-20260508-100000.tar'])
    end

    it 'still writes the listing when the bulk download fails, leaving entries to heal later' do
      stub_list([obj('solectrus/solectrus-backup-20260508-100000.tar', 1024, '2026-05-08T10:00:00+00:00')])
      stub_download_failure

      described_class.refresh!

      entry = read_index['backups'].first
      aggregate_failures do
        expect(entry['filename']).to eq('solectrus-backup-20260508-100000.tar')
        expect(entry['files']).to be_empty
      end
    end
  end

  def write_index(data)
    FileUtils.mkdir_p(File.dirname(BackupRepository::Index.path))
    File.write(BackupRepository::Index.path, JSON.pretty_generate({ 'destination' => 's3' }.merge(data)))
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

  # A `list-objects-v2` output line as emitted by the run-1 listing script.
  def obj(key, size, mtime)
    "OBJ|#{key}|#{size}|#{mtime}"
  end

  # Stubs run 1 (the `list_objects` sidecar).
  def stub_list(lines, success: true)
    output = lines.empty? ? '' : "#{lines.join("\n")}\n"
    allow(Open3).to receive(:capture2)
      .and_return([output, instance_double(Process::Status, success?: success)])
  end

  # Stubs run 2 (the `aws s3 cp --recursive` sidecar): drops the given files
  # into the staging dir, exactly where the real sidecar would, so HELIOS
  # parses them for real.
  def stub_download(files = {})
    status = instance_double(Process::Status, success?: true, exitstatus: 0)
    allow(Open3).to receive(:capture2e) do
      files.each { |name, content| File.binwrite(File.join(described_class.directory, name), content) }
      ['', status]
    end
  end

  # Stubs run 2 as a failed download (no files land in the staging dir).
  def stub_download_failure
    status = instance_double(Process::Status, success?: false, exitstatus: 1)
    allow(Open3).to receive(:capture2e).and_return(['AccessDenied', status])
  end

  def stub_capture2e(success:, output: '')
    status = instance_double(Process::Status, success?: success, exitstatus: success ? 0 : 1)
    allow(Open3).to receive(:capture2e).and_return([output, status])
  end

  # A valid HELIOS backup tar — config.yaml resolves the image tags, the
  # dump entries exercise entry parsing.
  def sample_tar(influxdb: 'influxdb:2-alpine', postgresql: 'postgres:18-alpine')
    entries = {
      'helios/config.yaml' => { 'influxdb' => { 'image' => influxdb },
                                'postgresql' => { 'image' => postgresql } }.to_yaml,
      'solectrus-postgresql-backup-2026-05-08.sql.gz' => 'pg-dump',
      'solectrus-influxdb-backup-2026-05-08.tar.gz' => 'influx-export',
    }
    StringIO.new.tap do |io|
      Gem::Package::TarWriter.new(io) do |tar|
        entries.each { |name, content| tar.add_file_simple(name, 0o644, content.bytesize) { |e| e.write(content) } }
      end
    end.string
  end

  def valid_backup
    {
      'destination' => 's3',
      'aws_bucket' => bucket,
      'aws_access_key_id' => 'AKIA',
      'aws_secret_access_key' => 'secret',
      'aws_region' => 'eu-central-1',
    }
  end
end
