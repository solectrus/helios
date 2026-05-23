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
class Backup < ApplicationRecord
  enum :destination, { local: 'local', external: 'external', s3: 's3' }

  scope :for_destination, lambda { |destination, **coords|
    where(
      destination: destination,
      external_path: coords[:external_path],
      s3_endpoint_url: coords[:s3_endpoint_url],
      s3_bucket: coords[:s3_bucket],
      s3_prefix: coords[:s3_prefix],
    )
  }
  scope :newest_first, -> { order(created_at: :desc, filename: :desc) }

  validates :filename, presence: true

  serialize :files, coder: JSON, type: Array, default: []

  def to_param = ::File.basename(filename, '.tar')

  def postgresql_bytes
    entry_bytes(BackupRepository::POSTGRESQL_ENTRY_PATTERN)
  end

  def influxdb_bytes
    entry_bytes(BackupRepository::INFLUXDB_ENTRY_PATTERN)
  end

  private

  def entry_bytes(pattern)
    files.find { |entry| entry['name']&.match?(pattern) }&.dig('bytes')
  end
end
