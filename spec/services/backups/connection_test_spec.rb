RSpec.describe Backups::ConnectionTest do
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
    let(:s3_client) { Aws::S3::Client.new(stub_responses: true, region: 'eu-central-1') }
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

    before { allow(Aws::S3::Client).to receive(:new).and_return(s3_client) }

    def probe(values)
      tester.call(check: 'aws_credentials', values: values)
    end

    it 'reports incomplete when any required field is blank' do
      allow(Aws::S3::Client).to receive(:new).and_call_original
      result = probe(full_values.merge('aws_secret_access_key' => ''))
      expect(result).to have_attributes(ok: false, reason: :incomplete)
      expect(s3_client.api_requests).to be_empty
    end

    it 'reports reachable on a successful list call' do
      s3_client.stub_responses(:list_objects_v2, contents: [])
      expect(probe(full_values)).to have_attributes(ok: true, reason: :s3_reachable)
    end

    it 'maps NoSuchBucket to s3_bucket_missing' do
      s3_client.stub_responses(:list_objects_v2, 'NoSuchBucket')
      expect(probe(full_values)).to have_attributes(ok: false, reason: :s3_bucket_missing)
    end

    it 'maps InvalidAccessKeyId to s3_invalid_credentials' do
      s3_client.stub_responses(:list_objects_v2, 'InvalidAccessKeyId')
      expect(probe(full_values)).to have_attributes(ok: false, reason: :s3_invalid_credentials)
    end

    it 'maps SignatureDoesNotMatch to s3_invalid_credentials' do
      s3_client.stub_responses(:list_objects_v2, 'SignatureDoesNotMatch')
      expect(probe(full_values)).to have_attributes(ok: false, reason: :s3_invalid_credentials)
    end

    it 'maps AccessDenied to s3_access_denied' do
      s3_client.stub_responses(:list_objects_v2, 'AccessDenied')
      expect(probe(full_values)).to have_attributes(ok: false, reason: :s3_access_denied)
    end

    it 'maps networking errors to s3_endpoint_unreachable' do
      net_error = Seahorse::Client::NetworkingError.new(StandardError.new('connect failed'))
      s3_client.stub_responses(:list_objects_v2, net_error)
      expect(probe(full_values.merge('s3_endpoint_url' => 'https://minio.example.com')))
        .to have_attributes(ok: false, reason: :s3_endpoint_unreachable)
    end

    it 'falls back to s3_error for unknown service errors' do
      s3_client.stub_responses(:list_objects_v2, 'InternalError')
      expect(probe(full_values)).to have_attributes(ok: false, reason: :s3_error)
    end

    it 'sends the bucket and prefix to S3' do
      s3_client.stub_responses(:list_objects_v2, contents: [])
      probe(full_values)
      req = s3_client.api_requests.find { |r| r[:operation_name] == :list_objects_v2 }
      expect(req[:params]).to include(bucket: 'my-backups', prefix: 'solectrus/', max_keys: 1)
    end

    it 'configures path-style addressing when an endpoint URL is set' do
      captured = nil
      allow(Aws::S3::Client).to receive(:new) do |**opts|
        captured = opts
        s3_client
      end
      s3_client.stub_responses(:list_objects_v2, contents: [])

      probe(full_values.merge('s3_endpoint_url' => 'https://minio.example.com'))

      expect(captured).to include(endpoint: 'https://minio.example.com', force_path_style: true)
    end
  end

  def stub_probe(exitstatus:, output:)
    status = instance_double(Process::Status, exitstatus: exitstatus, success?: exitstatus.zero?)
    allow(Open3).to receive(:capture2e).and_return([output, status])
  end
end
