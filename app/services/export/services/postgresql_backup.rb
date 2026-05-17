module Export
  module Services
    class PostgresqlBackup < Base
      def self.service_name
        'postgresql-backup'
      end

      def self.config_keys
        %w[backup postgresql]
      end

      def self.comment
        'PostgreSQL Backup — Automated backup to S3'
      end

      def self.enabled?(configuration)
        !configuration.collectors_only? && configuration.configured?(:backup)
      end

      def to_h
        {
          image: backup_image,
          environment: backup_environment,
          depends_on: healthy_depends_on(%i[postgresql]),
          restart: 'unless-stopped',
        }
      end

      private

      # postgres-s3-backup runs `pg_dump`, which must match the database's
      # major version. Derive the tag from the configured PostgreSQL image
      # rather than storing it — mirrors Postgresql#container_data_path.
      def backup_image
        major = configuration.postgresql.image.to_s[/postgres:(\d+)/, 1]
        DockerImages.postgresql_backup_for(major)
      end

      def backup_environment
        [
          'POSTGRES_HOST=postgresql',
          'POSTGRES_DATABASE=solectrus',
          'POSTGRES_USER=postgres',
          'POSTGRES_PASSWORD',
          'S3_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}',
          'S3_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}',
          'S3_REGION=${AWS_REGION}',
          'S3_BUCKET=${AWS_BUCKET}',
          'S3_PREFIX=postgresql',
          'SCHEDULE=@daily',
        ]
      end
    end
  end
end
