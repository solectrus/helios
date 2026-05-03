module Export
  class Env
    class Backup < Section
      def call
        env.add_section('S3 Backup')
        entry('AWS_ACCESS_KEY_ID', configuration.backup.aws_access_key_id,
              'AWS access key for S3 backup')
        entry('AWS_SECRET_ACCESS_KEY', configuration.backup.aws_secret_access_key,
              'AWS secret key — keep this confidential!')
        entry('AWS_REGION', configuration.backup.aws_region,
              'AWS region for S3 bucket')
        entry('AWS_BUCKET', configuration.backup.aws_bucket,
              'S3 bucket name for backups')
      end
    end
  end
end
