require 'rubygems/package'

RSpec.describe BackupRepository::S3 do
  let(:data_path) { Dir.mktmpdir }
  let(:host_data_path) { '/host/data' }
  let(:bucket) { 'my-backups' }
  let(:s3_client) { Aws::S3::Client.new(stub_responses: true, region: 'eu-central-1') }
  let(:filename) { 'solectrus-backup-20260508-100000.tar' }

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
    allow(RestoreRunner).to receive(:in_progress).and_return(nil)
    allow(described_class).to receive(:client).and_return(s3_client)
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

  describe '.normalize_prefix' do
    it 'strips leading and trailing slashes' do
      expect(described_class.normalize_prefix('/solectrus//')).to eq('solectrus')
    end

    it 'returns an empty string for nil or blank input' do
      expect(described_class.normalize_prefix(nil)).to eq('')
      expect(described_class.normalize_prefix('  ')).to eq('')
    end
  end

  describe '.all' do
    it 'returns DB rows scoped to the current bucket+prefix without contacting S3' do
      create_row('solectrus-backup-20260508-100000.tar')
      create_row('solectrus-backup-20260508-120000.tar')

      filenames = described_class.all.map(&:filename)

      expect(filenames).to eq(%w[solectrus-backup-20260508-120000.tar solectrus-backup-20260508-100000.tar])
      expect(s3_client.api_requests).to be_empty
    end

    it 'does not surface rows recorded for a different bucket' do
      create_row('solectrus-backup-20260508-100000.tar', bucket: 'other-bucket')

      expect(described_class.all).to be_empty
    end

    it 'returns an empty list when destination is not configured' do
      with_config_yaml('backup' => { 'destination' => 's3' })
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
    it 'issues a delete_objects call for the tar, then removes the DB row' do
      create_row(filename)

      described_class.destroy!(filename)

      delete_calls = s3_client.api_requests.select { |r| r[:operation_name] == :delete_objects }
      expect(delete_calls.size).to eq(1)
      keys = delete_calls.first[:params][:delete][:objects].pluck(:key)
      expect(keys).to contain_exactly("solectrus/#{filename}")
      expect(Backup.where(filename: filename)).not_to exist
    end

    it 'raises BackupRepository::Error and leaves the DB row in place when the S3 call fails' do
      create_row(filename)
      s3_client.stub_responses(:delete_objects, 'AccessDenied')

      expect { described_class.destroy!(filename) }
        .to raise_error(BackupRepository::Error, /AccessDenied/)
      expect(Backup.where(filename: filename)).to exist
    end

    it 'raises NotFound when no row exists' do
      expect { described_class.destroy!(filename) }
        .to raise_error(BackupRepository::NotFound)
    end
  end

  describe '.direct_download_url' do
    it 'returns a presigned URL pointing at the object key, with attachment disposition' do
      create_row(filename)

      url = described_class.direct_download_url(filename)
      uri = URI.parse(url)
      query = URI.decode_www_form(uri.query.to_s).to_h

      expect(uri.host).to eq("#{bucket}.s3.eu-central-1.amazonaws.com")
      expect(uri.path).to eq("/solectrus/#{filename}")
      expect(query['X-Amz-Expires']).to eq(BackupRepository::S3::DOWNLOAD_URL_TTL.to_i.to_s)
      expect(query['response-content-disposition']).to include("filename=\"#{filename}\"")
      expect(query['response-content-type']).to eq('application/x-tar')
    end

    it 'raises NotFound for an invalid filename' do
      expect { described_class.direct_download_url('garbage') }.to raise_error(BackupRepository::NotFound)
    end

    it 'raises NotFound when the destination is not configured' do
      with_config_yaml('backup' => { 'destination' => 's3' })
      expect { described_class.direct_download_url(filename) }.to raise_error(BackupRepository::NotFound)
    end

    it 'raises NotFound when no row is recorded for the filename' do
      expect { described_class.direct_download_url(filename) }.to raise_error(BackupRepository::NotFound)
    end
  end

  describe '.download' do
    it 'streams the object to the block' do
      create_row(filename)
      s3_client.stub_responses(:get_object, body: 'tar-bytes')

      chunks = []
      described_class.download(filename) { |chunk| chunks << chunk }

      expect(chunks.join).to eq('tar-bytes')
    end

    # The row says the backup exists, but the object is gone (deleted in the
    # bucket, or a lifecycle rule expired it).
    it 'raises NotFound when the object is gone from the bucket' do
      create_row(filename)
      s3_client.stub_responses(:get_object, 'NoSuchKey')

      expect { described_class.download(filename) { |chunk| chunk } }
        .to raise_error(BackupRepository::NotFound)
    end
  end

  describe '.read_archive_for' do
    it 'returns an empty archive when the destination is not configured' do
      with_config_yaml('backup' => { 'destination' => 's3' })

      expect(described_class.read_archive_for(filename)).to eq(BackupRepository::EMPTY_ARCHIVE)
    end

    it 'returns an empty archive when nothing is staged locally' do
      expect(described_class.read_archive_for(filename)).to eq(BackupRepository::EMPTY_ARCHIVE)
    end

    it 'reads the staged copy the download left behind' do
      write_staged_tar(filename)

      expect(described_class.read_archive_for(filename).config).to eq('system' => {})
    end
  end

  describe '.upload_from_staging!' do
    it 'raises a repository error when S3 rejects the upload' do
      write_staged_tar(filename)
      s3_client.stub_responses(:put_object, 'AccessDenied')

      expect { described_class.upload_from_staging!(filename) }
        .to raise_error(BackupRepository::Error, /AccessDenied/)
    end
  end

  describe '.record_from_staging!' do
    # Right after an upload the tar is still on disk; reading it there saves
    # downloading back what was just sent.
    it 'records the row from the staged copy' do
      write_staged_tar(filename)

      described_class.record_from_staging!(filename)

      expect(described_class.find!(filename).files.pluck('name')).to eq(['helios/config.yaml'])
    end

    it 'records nothing when the staged copy is already gone' do
      expect(described_class.record_from_staging!(filename)).to be_nil
      expect(Backup.count).to eq(0)
    end

    it 'rejects a filename that is not a backup' do
      expect { described_class.record_from_staging!('garbage.tar') }.to raise_error(BackupRepository::NotFound)
    end
  end

  # The SDK reports one entry per multipart part; the UI only wants a total.
  describe 'upload progress' do
    it 'sums the per-part numbers into one pair' do
      reported = nil

      described_class.send(:progress_bridge, ->(done, total) { reported = [done, total] })
                     .call([10, 20], [100, 200])

      expect(reported).to eq([30, 300])
    end

    it 'passes no callback through when the caller wants no progress' do
      expect(described_class.send(:progress_bridge, nil)).to be_nil
    end
  end

  describe '.download_to_staging!' do
    it 'reports progress against the size the caller knows' do
      s3_client.stub_responses(:get_object, body: 'tar-bytes')
      progress = []

      described_class.download_to_staging!(
        filename, progress_callback: ->(done, total) { progress << [done, total] }, total: 9
      )

      expect(progress.last).to eq([9, 9])
      expect(File.read(described_class.staging_path(filename))).to eq('tar-bytes')
    end
  end

  describe '.remove_files!' do
    # Pruning deletes what the DB lists; an object someone already removed in
    # the bucket must not abort the prune.
    it 'ignores objects that are already gone' do
      s3_client.stub_responses(:delete_objects, 'NoSuchKey')

      expect { described_class.remove_files!(['solectrus-backup-20260508-100000.tar']) }.not_to raise_error
    end
  end

  describe '.error_message' do
    it 'reads the backup runner error from RunnerLog' do
      RunnerLog.record_error!(:backup, 'Disk full')
      expect(BackupRepository.error_message).to eq('Disk full')
    end

    it 'returns nil when no error was recorded' do
      expect(BackupRepository.error_message).to be_nil
    end
  end

  describe '.record_backup!' do
    it 'downloads the tar to staging, parses it locally, then inserts a row and clears staging' do
      tar_bytes = sample_tar(influxdb: 'influxdb:2.9-alpine', postgresql: 'postgres:18-alpine')
      s3_client.stub_responses(:get_object, body: tar_bytes)

      described_class.record_backup!(filename)

      backup = described_class.find!(filename)
      expect(backup.bytes).to eq(tar_bytes.bytesize)
      expect(backup.influxdb_image).to eq('influxdb:2.9-alpine')
      expect(backup.postgresql_image).to eq('postgres:18-alpine')
      expect(File).not_to exist(File.join(described_class.directory, filename))
    end

    it 'records the destination coordinates so a bucket change hides the row' do
      s3_client.stub_responses(:get_object, body: sample_tar)

      described_class.record_backup!(filename)

      row = Backup.find_by(filename: filename)
      expect(row.destination).to eq('s3')
      expect(row.s3_bucket).to eq(bucket)
      expect(row.s3_prefix).to eq('solectrus')
    end

    it 'rejects filenames that do not match the canonical pattern' do
      expect { described_class.record_backup!('garbage.tar') }.to raise_error(BackupRepository::NotFound)
    end

    it 'is a no-op when the S3 download fails' do
      s3_client.stub_responses(:get_object, 'NoSuchKey')

      expect { described_class.record_backup!(filename) }.not_to raise_error
      expect(Backup.count).to eq(0)
      expect(File).not_to exist(File.join(described_class.directory, filename))
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

    it 'inserts the Backup row when the expected tar is available in S3' do
      described_class.mark_pending!(filename)
      # error files live in the local staging dir now (backup.sh writes
      # them there); no S3 fetches happen for them. Only the tar download
      # by record_backup! hits S3.
      s3_client.stub_responses(:get_object, body: sample_tar)

      described_class.detect_completion!

      expect(Backup.find_by(filename: filename)).to be_present
      expect(File).not_to exist(described_class.pending_marker_path)
    end

    it 'captures a runtime error.txt into RunnerLog when the run failed' do
      described_class.mark_pending!(filename)
      runtime_dir = File.join(Rails.configuration.data_path, 'helios', 'runners')
      FileUtils.mkdir_p(runtime_dir)
      File.write(File.join(runtime_dir, 'error.txt'), 'Disk full')

      described_class.detect_completion!

      expect(RunnerLog.message_for(:backup)).to eq('Disk full')
      expect(Backup.count).to eq(0)
    end

    it 'records "incomplete" once the retry budget is exhausted with no tar and no error' do
      described_class.mark_pending!(filename)
      s3_client.stub_responses(:get_object, 'NoSuchKey')

      BackupRepository::Tracking::RECORDING_MAX_ATTEMPTS.times { described_class.detect_completion! }

      expect(RunnerLog.message_for(:backup)).to eq(I18n.t('backups.runner.errors.incomplete'))
    end
  end

  describe '.client' do
    before { allow(described_class).to receive(:client).and_call_original }

    it 'forces path-style addressing when an endpoint_url is configured' do
      with_config_yaml('backup' => valid_backup.merge('s3_endpoint_url' => 'http://minio.local:9000'))

      client = described_class.client
      expect(client.config.endpoint.to_s).to eq('http://minio.local:9000')
      expect(client.config.force_path_style).to be(true)
    end

    it 'leaves AWS defaults in place when no endpoint_url is configured' do
      with_config_yaml('backup' => valid_backup)

      client = described_class.client
      expect(client.config.region).to eq('eu-central-1')
      expect(client.config.force_path_style).to be(false)
    end
  end

  def write_staged_tar(filename)
    FileUtils.mkdir_p(described_class.directory)
    File.binwrite(described_class.staging_path(filename), config_only_tar)
  end

  def create_row(filename, bucket: self.bucket, prefix: 'solectrus', endpoint_url: nil)
    Backup.create!(
      filename: filename,
      bytes: 1024,
      created_at: BackupRepository.created_at_from(filename) || Time.current,
      destination: 's3',
      s3_bucket: bucket,
      s3_prefix: prefix,
      s3_endpoint_url: endpoint_url,
      files: [{ 'name' => 'helios/config.yaml', 'bytes' => 10 }],
    )
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
