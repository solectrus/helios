module Import
  class ConfigurationImporter
    class BackupExtractor
      include Helpers

      def initialize(reader)
        @reader = reader
      end

      def section_data
        return unless @reader.services.key?('postgresql-backup')

        # The postgres-s3-backup image is not imported: it is derived at
        # export time from the PostgreSQL major version (its pg_dump must
        # match the server) — see Export::Services::PostgresqlBackup.
        {
          'influxdb' => image_data_for('influxdb-backup').presence,
          'aws_access_key_id' => @reader.raw_env['AWS_ACCESS_KEY_ID'],
          'aws_secret_access_key' => @reader.raw_env['AWS_SECRET_ACCESS_KEY'],
          'aws_region' => @reader.raw_env['AWS_REGION'],
          'aws_bucket' => @reader.raw_env['AWS_BUCKET'],
        }.compact
      end
    end
  end
end
