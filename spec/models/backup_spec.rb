# == Schema Information
#
# Table name: backups
# Database name: primary
#
#  id               :integer          not null, primary key
#  bytes            :bigint           not null
#  destination      :string           not null
#  external_path    :string
#  filename         :string           not null
#  files            :text
#  influxdb_image   :string
#  postgresql_image :string
#  s3_bucket        :string
#  s3_endpoint_url  :string
#  s3_prefix        :string
#  created_at       :datetime         not null
#
# Indexes
#
#  index_backups_on_destination_and_created_at  (destination,created_at)
#  index_backups_on_destination_and_filename    (destination,external_path,s3_endpoint_url,s3_bucket,s3_prefix,filename) UNIQUE
#
RSpec.describe Backup do
  let(:filename) { 'solectrus-backup-20260508-110000.tar' }

  def valid_attrs(**overrides)
    {
      filename: filename,
      bytes: 1024,
      destination: 'local',
      files: [],
    }.merge(overrides)
  end

  describe 'validations' do
    it 'requires a filename' do
      record = described_class.new(valid_attrs(filename: nil))
      expect(record).not_to be_valid
      expect(record.errors[:filename]).to be_present
    end
  end

  describe 'destination enum' do
    it 'accepts each known destination' do
      %i[local external s3].each do |destination|
        expect(described_class.new(valid_attrs(destination: destination))).to be_valid
      end
    end

    it 'raises on an unknown destination' do
      expect { described_class.new(valid_attrs(destination: 'ftp')) }.to raise_error(ArgumentError)
    end
  end

  describe '#created_at' do
    it 'keeps the explicit value instead of falling back to Time.current' do
      taken_at = Time.zone.parse('2026-05-08 11:00:00')
      record = described_class.create!(valid_attrs(created_at: taken_at))

      expect(record.reload.created_at).to eq(taken_at)
    end
  end

  describe '#to_param' do
    it 'strips the .tar suffix so the URL is /backups/<timestamp>' do
      record = described_class.new(filename: filename)
      expect(record.to_param).to eq('solectrus-backup-20260508-110000')
    end
  end

  describe '#files' do
    it 'returns the persisted entries as hashes' do
      record = described_class.new(files: [{ 'name' => 'helios/config.yaml', 'bytes' => 42 }])

      expect(record.files).to eq([{ 'name' => 'helios/config.yaml', 'bytes' => 42 }])
    end

    it 'returns an empty array when no entries are persisted' do
      expect(described_class.new.files).to eq([])
    end
  end

  describe '#postgresql_bytes / #influxdb_bytes' do
    it 'returns the matching entry size when the patterned filename is present' do
      record = described_class.new(files: [
                                     { 'name' => 'solectrus-postgresql-backup-2026-05-08.sql.gz', 'bytes' => 100 },
                                     { 'name' => 'solectrus-influxdb-backup-2026-05-08/bolt.gz', 'bytes' => 120 },
                                     { 'name' => 'solectrus-influxdb-backup-2026-05-08/data.tar.gz', 'bytes' => 80 },
                                   ])

      expect(record.postgresql_bytes).to eq(100)
      expect(record.influxdb_bytes).to eq(200)
    end

    it 'returns nil when no matching entry is present' do
      record = described_class.new(files: [{ 'name' => 'helios/config.yaml', 'bytes' => 42 }])

      expect(record.postgresql_bytes).to be_nil
      expect(record.influxdb_bytes).to be_nil
    end
  end

  describe '.for_destination' do
    before do
      described_class.create!(valid_attrs(filename: 'solectrus-backup-20260508-100000.tar',
                                          destination: 'local'))
      described_class.create!(valid_attrs(filename: 'solectrus-backup-20260508-110000.tar',
                                          destination: 'external', external_path: '/mnt/nas'))
      described_class.create!(valid_attrs(filename: 'solectrus-backup-20260508-120000.tar',
                                          destination: 's3', s3_bucket: 'bkts', s3_prefix: 'sol',
                                          s3_endpoint_url: nil))
    end

    it 'returns only the local rows when called with empty coords' do
      filenames = described_class.for_destination('local').map(&:filename)
      expect(filenames).to contain_exactly('solectrus-backup-20260508-100000.tar')
    end

    it 'matches external rows by external_path' do
      filenames = described_class.for_destination('external', external_path: '/mnt/nas').map(&:filename)
      expect(filenames).to contain_exactly('solectrus-backup-20260508-110000.tar')
    end

    it 'does not match an external row when external_path differs' do
      expect(described_class.for_destination('external', external_path: '/other')).to be_empty
    end

    it 'matches S3 rows by bucket + prefix + endpoint' do
      filenames = described_class
                  .for_destination('s3', s3_bucket: 'bkts', s3_prefix: 'sol', s3_endpoint_url: nil)
                  .map(&:filename)
      expect(filenames).to contain_exactly('solectrus-backup-20260508-120000.tar')
    end
  end

  describe '.newest_first' do
    it 'orders by created_at desc, filename desc as the tie-breaker' do
      taken_at = Time.zone.parse('2026-05-08 12:00:00')
      described_class.create!(valid_attrs(filename: 'solectrus-backup-20260508-120001.tar', created_at: taken_at))
      described_class.create!(valid_attrs(filename: 'solectrus-backup-20260508-120002.tar', created_at: taken_at))
      described_class.create!(valid_attrs(filename: 'solectrus-backup-20260508-110000.tar',
                                          created_at: Time.zone.parse('2026-05-08 11:00:00')))

      expect(described_class.newest_first.map(&:filename)).to eq(%w[
                                                                   solectrus-backup-20260508-120002.tar
                                                                   solectrus-backup-20260508-120001.tar
                                                                   solectrus-backup-20260508-110000.tar
                                                                 ])
    end
  end
end
