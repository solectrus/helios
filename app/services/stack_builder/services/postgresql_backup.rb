class StackBuilder
  module Services
    class PostgresqlBackup < Base
      def self.service_name
        'postgresql-backup'
      end

      def self.comment
        'Automated PostgreSQL backup to S3'
      end

      def self.enabled?(configuration)
        configuration.backup.enabled == true
      end

      def to_h
        {
          image: configuration.backup.postgresql.image,
          environment: postgresql_backup_environment,
          depends_on: healthy_depends_on(%i[postgresql]),
          restart: 'unless-stopped',
        }
      end

      private

      def postgresql_backup_environment
        {
          'POSTGRES_HOST' => 'postgresql',
          'POSTGRES_DATABASE' => 'solectrus',
          'POSTGRES_USER' => 'postgres',
          'POSTGRES_PASSWORD' => '${POSTGRES_PASSWORD}',
          'S3_ACCESS_KEY_ID' => '${AWS_ACCESS_KEY_ID}',
          'S3_SECRET_ACCESS_KEY' => '${AWS_SECRET_ACCESS_KEY}',
          'S3_REGION' => '${AWS_REGION}',
          'S3_BUCKET' => '${AWS_BUCKET}',
          'S3_PREFIX' => 'postgresql',
          'SCHEDULE' => '@daily',
        }
      end
    end
  end
end
