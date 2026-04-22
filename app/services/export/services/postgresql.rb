module Export
  module Services
    class Postgresql < Base
      def self.service_name
        'postgresql'
      end

      def self.comment
        'PostgreSQL — Relational database for daily summaries, electricity prices, and settings'
      end

      def data_directories
        managed_data_directory
      end

      def to_h
        {
          image: configuration.postgresql.image,
          environment: [
            'POSTGRES_PASSWORD',
            'POSTGRES_DB=solectrus',
          ],
          volumes: [bind_mount('/var/lib/postgresql')],
          restart: 'unless-stopped',
          healthcheck: healthcheck('CMD-SHELL', 'pg_isready -U postgres'),
        }
      end
    end
  end
end
