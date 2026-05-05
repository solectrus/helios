module Export
  module Services
    class Postgresql < Base
      def self.service_name
        'postgresql'
      end

      def self.config_keys
        ['postgresql']
      end

      def self.volume_env_key
        'DB_VOLUME_PATH'
      end

      def self.comment
        'PostgreSQL — Relational database for daily summaries, electricity prices, and settings'
      end

      def self.enabled?(configuration)
        !configuration.collectors_only?
      end

      def data_directories
        managed_data_directory
      end

      def to_h
        {
          image: configuration.postgresql.image,
          environment: postgres_environment,
          volumes: [bind_mount('/var/lib/postgresql')],
          restart: 'unless-stopped',
          healthcheck: healthcheck('CMD-SHELL', 'pg_isready -U postgres'),
        }
      end

      private

      def postgres_environment
        env = ['TZ', 'POSTGRES_PASSWORD', 'POSTGRES_DB=solectrus']
        env << 'PGDATA' if configuration.postgresql.pgdata.present?
        env
      end
    end
  end
end
