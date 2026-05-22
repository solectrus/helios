RSpec.describe Backup::ConnectionTest do
  subject(:tester) { described_class.new }

  describe 'external_path check' do
    def probe(path)
      tester.call(check: 'external_path', values: { 'external_path' => path })
    end

    it 'reports incomplete when path is blank' do
      expect(probe('')).to have_attributes(ok: false, reason: :incomplete)
    end

    it 'rejects relative paths up front (no docker call)' do
      allow(Open3).to receive(:capture2e)
      expect(probe('relative/path')).to have_attributes(ok: false, reason: :backup_path_not_absolute)
      expect(Open3).not_to have_received(:capture2e)
    end

    it 'rejects paths with shell-significant characters up front' do
      allow(Open3).to receive(:capture2e)
      expect(probe('/mnt/with spaces')).to have_attributes(ok: false, reason: :backup_path_invalid_chars)
      expect(Open3).not_to have_received(:capture2e)
    end

    it 'reports writable on sidecar exit 0' do
      stub_probe(exitstatus: 0, output: '')
      expect(probe('/mnt/backups')).to have_attributes(ok: true, reason: :backup_path_writable)
    end

    it 'maps sidecar exit 10 to backup_path_not_directory' do
      stub_probe(exitstatus: 10, output: '')
      expect(probe('/mnt/backups')).to have_attributes(ok: false, reason: :backup_path_not_directory)
    end

    it 'maps sidecar exit 11 to backup_path_not_writable' do
      stub_probe(exitstatus: 11, output: '')
      expect(probe('/mnt/backups')).to have_attributes(ok: false, reason: :backup_path_not_writable)
    end

    it 'maps a docker "no such file" error to backup_path_missing' do
      stub_probe(exitstatus: 125, output: 'docker: Error: stat /mnt/backups: no such file or directory.')
      expect(probe('/mnt/backups')).to have_attributes(ok: false, reason: :backup_path_missing)
    end

    it 'falls back to backup_path_error for unrecognized failures' do
      stub_probe(exitstatus: 2, output: 'unexpected gibberish')
      expect(probe('/mnt/backups')).to have_attributes(ok: false, reason: :backup_path_error)
    end

    it 'reports error when the docker call raises' do
      allow(Open3).to receive(:capture2e).and_raise(Errno::ENOENT, 'docker missing')
      expect(probe('/mnt/backups')).to have_attributes(ok: false, reason: :backup_path_error)
    end
  end

  describe 'aws_credentials check' do
    let(:full_values) do
      {
        'aws_access_key_id' => 'AKIA...',
        'aws_secret_access_key' => 'secret',
        'aws_region' => 'eu-central-1',
        'aws_bucket' => 'my-backups',
        's3_prefix' => 'solectrus/',
        's3_endpoint_url' => '',
      }
    end

    def probe(values)
      tester.call(check: 'aws_credentials', values: values)
    end

    it 'reports incomplete when any required field is blank' do
      allow(Open3).to receive(:capture2e)
      result = probe(full_values.merge('aws_secret_access_key' => ''))
      expect(result).to have_attributes(ok: false, reason: :incomplete)
      expect(Open3).not_to have_received(:capture2e)
    end

    it 'reports reachable on sidecar success' do
      stub_probe(exitstatus: 0, output: "2026-05-08 12:00:00  1024 solectrus-backup-20260508-120000.tar\n")
      expect(probe(full_values)).to have_attributes(ok: true, reason: :s3_reachable)
    end

    it 'maps NoSuchBucket to s3_bucket_missing' do
      stub_probe(exitstatus: 255, output: 'An error occurred (NoSuchBucket) when calling the ListObjectsV2 operation')
      expect(probe(full_values)).to have_attributes(ok: false, reason: :s3_bucket_missing)
    end

    it 'maps InvalidAccessKeyId to s3_invalid_credentials' do
      stub_probe(exitstatus: 255, output: 'An error occurred (InvalidAccessKeyId)')
      expect(probe(full_values)).to have_attributes(ok: false, reason: :s3_invalid_credentials)
    end

    it 'maps SignatureDoesNotMatch to s3_invalid_credentials' do
      stub_probe(exitstatus: 255, output: 'An error occurred (SignatureDoesNotMatch)')
      expect(probe(full_values)).to have_attributes(ok: false, reason: :s3_invalid_credentials)
    end

    it 'maps AccessDenied to s3_access_denied' do
      stub_probe(exitstatus: 255, output: 'An error occurred (AccessDenied)')
      expect(probe(full_values)).to have_attributes(ok: false, reason: :s3_access_denied)
    end

    it 'maps endpoint connection failures to s3_endpoint_unreachable' do
      stub_probe(exitstatus: 255, output: 'Could not connect to the endpoint URL')
      expect(probe(full_values.merge('s3_endpoint_url' => 'https://minio.example.com')))
        .to have_attributes(ok: false, reason: :s3_endpoint_unreachable)
    end

    it 'falls back to s3_error for unknown failures' do
      stub_probe(exitstatus: 1, output: 'unexpected output')
      expect(probe(full_values)).to have_attributes(ok: false, reason: :s3_error)
    end

    it 'targets the bucket and prefix in the probe command' do
      stub_probe(exitstatus: 0, output: '')
      probe(full_values)
      expect(Open3).to have_received(:capture2e) do |*args|
        expect(args).to include('s3api', 'list-objects-v2', '--bucket', 'my-backups')
        expect(args).to include('--prefix', 'solectrus/')
      end
    end

    it 'forwards the endpoint URL via env when set' do
      stub_probe(exitstatus: 0, output: '')
      probe(full_values.merge('s3_endpoint_url' => 'https://minio.example.com'))
      expect(Open3).to have_received(:capture2e) do |*args|
        expect(args).to include('-e', 'AWS_ENDPOINT_URL=https://minio.example.com')
      end
    end

    it 'omits the endpoint env when blank' do
      stub_probe(exitstatus: 0, output: '')
      probe(full_values.merge('s3_endpoint_url' => ''))
      expect(Open3).to have_received(:capture2e) do |*args|
        expect(args.grep(/AWS_ENDPOINT_URL/)).to be_empty
      end
    end

    it 'reports error when the docker call raises' do
      allow(Open3).to receive(:capture2e).and_raise(Errno::ENOENT, 'docker missing')
      expect(probe(full_values)).to have_attributes(ok: false, reason: :s3_error)
    end
  end

  def stub_probe(exitstatus:, output:)
    status = instance_double(Process::Status, exitstatus: exitstatus, success?: exitstatus.zero?)
    allow(Open3).to receive(:capture2e).and_return([output, status])
  end
end
