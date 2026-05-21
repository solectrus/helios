module Import
  class ConfigurationImporter
    class BackupExtractor
      include Helpers

      def initialize(reader)
        @reader = reader
      end

      def section_data
        return unless @reader.services.key?('postgresql-backup')

        # The S3-sidecar backup services (postgres-s3-backup / influxdb2-s3-backup)
        # are no longer rendered into compose.yaml, but their AWS credentials
        # from a legacy installation's .env are preserved so they can be picked
        # up by the new backup configuration.
        {
          'aws_access_key_id' => @reader.raw_env['AWS_ACCESS_KEY_ID'],
          'aws_secret_access_key' => @reader.raw_env['AWS_SECRET_ACCESS_KEY'],
          'aws_region' => @reader.raw_env['AWS_REGION'],
          'aws_bucket' => @reader.raw_env['AWS_BUCKET'],
        }.compact
      end
    end
  end
end
