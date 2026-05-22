require 'securerandom'

# Integration coverage for the S3 backup adapter against a real
# S3-compatible server (MinIO) and the real, pinned `amazon/aws-cli`
# image.
#
# This is the guard for the BackupRepository::S3::IMAGE pin: the adapter
# parses aws-cli's text output (`list-objects-v2 --query --output text`)
# and classifies its error wording with regexes. A version bump that
# changed either would break here, before it ever reaches a user.
#
# Tagged :integration by its spec/integration/ location — runs on CI and
# locally only with `--tag integration`. Skipped when Docker is absent.
RSpec.describe BackupRepository::S3 do
  let(:bucket) { "helios-itest-#{SecureRandom.hex(6)}" }
  let(:prefix) { 'solectrus' }

  before(:all) { start_s3_server! if docker_available? }

  after(:all) { stop_s3_server! }

  before do
    skip_without_docker
    configure_s3!
    s3_create_bucket!(bucket)
  end

  describe '.all / .refresh!' do
    it 'returns an empty list for an empty bucket' do
      expect(described_class.all).to eq([])
    end

    it 'lists and fully parses a stored backup tar' do
      s3_put_object!(bucket:, key: "#{prefix}/#{filename}", body: backup_tar)

      backups = described_class.all
      aggregate_failures do
        expect(backups.map(&:filename)).to eq([filename])
        expect(backups.first.bytes).to eq(backup_tar.bytesize)
        expect(backups.first.files.map(&:name)).to include('helios/config.yaml')
        expect(backups.first.influxdb_image).to eq('influxdb:2-alpine')
        expect(backups.first.postgresql_image).to eq('postgres:18-alpine')
      end
    end

    it 'orders backups newest first' do
      older = 'solectrus-backup-20260508-100000.tar'
      newer = 'solectrus-backup-20260508-140000.tar'
      s3_put_object!(bucket:, key: "#{prefix}/#{older}", body: backup_tar)
      s3_put_object!(bucket:, key: "#{prefix}/#{newer}", body: backup_tar)

      expect(described_class.all.map(&:filename)).to eq([newer, older])
    end
  end

  describe '.find!' do
    it 'returns the stored backup' do
      s3_put_object!(bucket:, key: "#{prefix}/#{filename}", body: backup_tar)

      expect(described_class.find!(filename).filename).to eq(filename)
    end

    it 'raises NotFound when the backup is absent' do
      expect { described_class.find!(filename) }.to raise_error(BackupRepository::NotFound)
    end
  end

  describe '.download' do
    it 'streams the stored tar back byte-for-byte' do
      s3_put_object!(bucket:, key: "#{prefix}/#{filename}", body: backup_tar)

      streamed = +''
      described_class.download(filename) { |chunk| streamed << chunk }
      expect(streamed.b).to eq(backup_tar.b)
    end
  end

  describe '.destroy!' do
    it 'removes the object from the bucket and the index' do
      s3_put_object!(bucket:, key: "#{prefix}/#{filename}", body: backup_tar)
      described_class.all # warm the index

      described_class.destroy!(filename)

      aggregate_failures do
        expect(s3_object_keys(bucket)).not_to include("#{prefix}/#{filename}")
        expect(described_class.all).to eq([])
      end
    end
  end

  describe '.prune!' do
    it 'deletes all but the newest backups' do
      %w[
        solectrus-backup-20260508-100000.tar
        solectrus-backup-20260508-120000.tar
        solectrus-backup-20260508-140000.tar
      ].each { |name| s3_put_object!(bucket:, key: "#{prefix}/#{name}", body: backup_tar) }
      described_class.all # warm the index

      described_class.prune!(keep: 1)

      expect(s3_object_keys(bucket)).to contain_exactly("#{prefix}/solectrus-backup-20260508-140000.tar")
    end
  end

  describe '.error_message / .clear_error!' do
    it 'reads the framed error file from the bucket' do
      s3_put_object!(bucket:, key: "#{prefix}/error.txt", body: "Disk full\n")

      expect(described_class.error_message).to eq('Disk full')
    end

    it 'clears the error file' do
      s3_put_object!(bucket:, key: "#{prefix}/error.txt", body: "Disk full\n")
      described_class.all # warm the index

      described_class.clear_error!

      aggregate_failures do
        expect(s3_object_keys(bucket)).not_to include("#{prefix}/error.txt")
        expect(described_class.error_message).to be_nil
      end
    end
  end

  describe 'Backup::ConnectionTest#aws_credentials' do
    it 'reports the bucket as reachable with valid credentials' do
      result = connection_test
      expect(result).to have_attributes(ok: true, reason: :s3_reachable)
    end

    it 'classifies a wrong secret as invalid credentials' do
      result = connection_test(secret: 'definitely-wrong-secret')
      expect(result).to have_attributes(ok: false, reason: :s3_invalid_credentials)
    end

    it 'classifies a missing bucket as bucket missing' do
      result = connection_test(bucket: 'no-such-bucket-here')
      expect(result).to have_attributes(ok: false, reason: :s3_bucket_missing)
    end
  end

  # --- helpers ---

  def filename
    'solectrus-backup-20260508-120000.tar'
  end

  def configure_s3!
    with_config_yaml('backup' => {
                       'destination' => 's3',
                       'aws_bucket' => bucket,
                       'aws_access_key_id' => s3_server.access_key,
                       'aws_secret_access_key' => s3_server.secret_key,
                       'aws_region' => 'us-east-1',
                       's3_prefix' => prefix,
                       's3_endpoint_url' => s3_server.endpoint,
                     })
    Current.reset
  end

  # A valid HELIOS backup tar: the config.yaml lets the adapter resolve the
  # InfluxDB / PostgreSQL image tags, the dump entries exercise entry parsing.
  def backup_tar
    @backup_tar ||= tar_archive(
      'helios/config.yaml' => { 'influxdb' => { 'image' => 'influxdb:2-alpine' },
                                'postgresql' => { 'image' => 'postgres:18-alpine' } }.to_yaml,
      'solectrus-postgresql-backup-2026-05-08.sql.gz' => 'postgres dump',
      'solectrus-influxdb-backup-2026-05-08.tar.gz' => 'influx export',
    )
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

  def connection_test(bucket: self.bucket, secret: s3_server.secret_key)
    Backup::ConnectionTest.new.call(
      check: 'aws_credentials',
      values: {
        'aws_access_key_id' => s3_server.access_key,
        'aws_secret_access_key' => secret,
        'aws_region' => 'us-east-1',
        'aws_bucket' => bucket,
        's3_prefix' => prefix,
        's3_endpoint_url' => s3_server.endpoint,
      },
    )
  end
end
