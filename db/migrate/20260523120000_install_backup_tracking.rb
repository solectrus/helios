require 'json'

class InstallBackupTracking < ActiveRecord::Migration[8.1]
  def up # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    create_table :backups do |t|
      t.string :filename, null: false
      t.bigint :bytes, null: false
      t.datetime :created_at, null: false

      t.string :destination, null: false
      t.string :external_path
      t.string :s3_endpoint_url
      t.string :s3_bucket
      t.string :s3_prefix

      t.string :influxdb_image
      t.string :postgresql_image

      t.text :files
    end

    add_index :backups,
              %i[destination external_path s3_endpoint_url s3_bucket s3_prefix filename],
              unique: true,
              name: 'index_backups_on_destination_and_filename'
    add_index :backups, %i[destination created_at]

    create_table :runner_logs do |t|
      t.string :kind, null: false
      t.text :last_error_message

      t.timestamps
    end

    add_index :runner_logs, :kind, unique: true

    import_legacy_backups_index
  end

  def down
    drop_table :runner_logs
    drop_table :backups
  end

  private

  # One-shot import of the pre-SQLite `backups_index.json` cache so users
  # upgrading don't lose their list. The JSON is deleted on success.
  def import_legacy_backups_index
    json_path = File.join(Rails.configuration.data_path, 'helios', 'backups_index.json')
    return unless File.exist?(json_path)

    parsed = parse_json(json_path)
    return unless parsed.is_a?(Hash)

    import_backups(parsed)
    import_errors(parsed)
    File.delete(json_path)
  rescue StandardError => e
    Rails.logger.warn("InstallBackupTracking legacy import skipped: #{e.message}")
  end

  def parse_json(path)
    JSON.parse(File.read(path))
  rescue JSON::ParserError
    nil
  end

  def import_backups(index)
    destination = index['destination'].to_s.presence || 'local'
    coords = legacy_coords(destination, index)

    Array(index['backups']).each do |entry|
      next if entry['filename'].blank?

      backup_row(destination, coords, entry).save!
    end
  end

  def legacy_coords(destination, index)
    case destination
    when 'external' then { external_path: index['external_path'] }
    when 's3'       then { s3_endpoint_url: index['endpoint_url'], s3_bucket: index['bucket'],
                           s3_prefix: index['prefix'] }
    else                 {}
    end
  end

  def backup_row(destination, coords, entry)
    record = Backup.find_or_initialize_by(destination: destination, filename: entry['filename'], **coords)
    record.assign_attributes(
      bytes: entry['bytes'].to_i,
      created_at: parse_time(entry['mtime']) || Time.current,
      influxdb_image: entry['influxdb_image'],
      postgresql_image: entry['postgresql_image'],
      files: Array(entry['files']),
    )
    record
  end

  def import_errors(index)
    RunnerLog.create!(kind: :backup, last_error_message: index['error_message']) if index['error_message'].present?
    return if index['restore_error_message'].blank?

    RunnerLog.create!(kind: :restore, last_error_message: index['restore_error_message'])
  end

  def parse_time(value)
    return nil if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end
end
