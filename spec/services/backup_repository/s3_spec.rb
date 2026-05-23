require 'rubygems/package'

RSpec.describe BackupRepository::S3 do
  let(:data_path) { Dir.mktmpdir }
  let(:host_data_path) { '/host/data' }
  let(:bucket) { 'my-backups' }
  let(:staging_dir) { File.join(data_path, 'helios', 'backups-staging') }

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
    it 'returns DB rows scoped to the current bucket+prefix without hitting docker' do
      create_row('solectrus-backup-20260508-100000.tar')
      create_row('solectrus-backup-20260508-120000.tar')
      allow(Open3).to receive(:capture2)
      allow(Open3).to receive(:capture2e)

      filenames = described_class.all.map(&:filename)

      expect(filenames).to eq(%w[solectrus-backup-20260508-120000.tar solectrus-backup-20260508-100000.tar])
      expect(Open3).not_to have_received(:capture2)
      expect(Open3).not_to have_received(:capture2e)
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
    it 'runs `aws s3 rm` via sidecar and removes the DB row' do
      create_row('solectrus-backup-20260508-100000.tar')
      stub_capture2e(success: true)

      described_class.destroy!('solectrus-backup-20260508-100000.tar')

      expect(Open3).to have_received(:capture2e).with(*captured_destroy_args)
      expect(Backup.where(filename: 'solectrus-backup-20260508-100000.tar')).not_to exist
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

    it 'raises BackupRepository::Error and leaves the DB row in place when the sidecar fails' do
      create_row('solectrus-backup-20260508-100000.tar')
      stub_capture2e(success: false, output: 'AccessDenied')

      expect { described_class.destroy!('solectrus-backup-20260508-100000.tar') }
        .to raise_error(BackupRepository::Error, /AccessDenied/)
      expect(Backup.where(filename: 'solectrus-backup-20260508-100000.tar')).to exist
    end

    it 'raises NotFound when no row exists' do
      expect { described_class.destroy!('solectrus-backup-20260508-100000.tar') }
        .to raise_error(BackupRepository::NotFound)
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
    let(:filename) { 'solectrus-backup-20260508-100000.tar' }

    it 'downloads the tar to staging, parses it locally, then inserts a row and clears staging' do
      tar_bytes = sample_tar(influxdb: 'influxdb:2.9-alpine', postgresql: 'postgres:18-alpine')
      stub_staging_download(filename => tar_bytes)

      described_class.record_backup!(filename)

      backup = described_class.find!(filename)
      expect(backup.bytes).to eq(tar_bytes.bytesize)
      expect(backup.influxdb_image).to eq('influxdb:2.9-alpine')
      expect(backup.postgresql_image).to eq('postgres:18-alpine')
      expect(File).not_to exist(File.join(described_class.directory, filename))
    end

    it 'records the destination coordinates so a bucket change hides the row' do
      stub_staging_download(filename => sample_tar)

      described_class.record_backup!(filename)

      row = Backup.find_by(filename: filename)
      expect(row.destination).to eq('s3')
      expect(row.s3_bucket).to eq(bucket)
      expect(row.s3_prefix).to eq('solectrus')
    end

    it 'rejects filenames that do not match the canonical pattern' do
      expect { described_class.record_backup!('garbage.tar') }.to raise_error(BackupRepository::NotFound)
    end

    it 'is a no-op when the download sidecar fails' do
      stub_capture2e(success: false, output: 'AccessDenied')

      expect { described_class.record_backup!(filename) }.not_to raise_error
      expect(Backup.count).to eq(0)
      expect(File).not_to exist(File.join(described_class.directory, filename))
    end
  end

  describe '.mark_pending! / .detect_completion!' do
    let(:filename) { 'solectrus-backup-20260508-100000.tar' }

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
      stub_capture2_sequence(
        ['', success_status], # restore-error.txt read
        ['', success_status], # error.txt read
      )
      stub_staging_download(filename => sample_tar)

      described_class.detect_completion!

      expect(Backup.find_by(filename: filename)).to be_present
      expect(File).not_to exist(described_class.pending_marker_path)
    end

    it 'captures error.txt into RunnerLog when the run failed' do
      described_class.mark_pending!(filename)
      stub_capture2_sequence(
        ['', success_status],          # restore-error.txt empty
        ['Disk full', success_status], # error.txt
      )
      stub_capture2e(success: true)

      described_class.detect_completion!

      expect(RunnerLog.message_for(:backup)).to eq('Disk full')
      expect(Backup.count).to eq(0)
    end

    it 'records "incomplete" when no tar and no error are present' do
      described_class.mark_pending!(filename)
      stub_capture2_sequence(
        ['', success_status], # restore-error.txt
        ['', success_status], # error.txt
      )
      stub_capture2e(success: false, output: 'NoSuchKey') # download_to_staging! fails → record_backup! returns nil

      described_class.detect_completion!

      expect(RunnerLog.message_for(:backup)).to eq(I18n.t('backups.runner.errors.incomplete'))
    end
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

  # Drops the given files into the staging dir, exactly where the real
  # aws s3 cp sidecar would, so HELIOS parses them for real. Uses the
  # live `described_class.directory` rather than a local lazy `let`,
  # because `with_config_yaml` resets Rails.configuration.data_path
  # mid-setup.
  def stub_staging_download(files = {})
    status = instance_double(Process::Status, success?: true, exitstatus: 0)
    allow(Open3).to receive(:capture2e) do
      FileUtils.mkdir_p(described_class.directory)
      files.each { |name, content| File.binwrite(File.join(described_class.directory, name), content) }
      ['', status]
    end
  end

  def stub_capture2_sequence(*responses)
    allow(Open3).to receive(:capture2).and_return(*responses)
  end

  def success_status
    instance_double(Process::Status, success?: true)
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
