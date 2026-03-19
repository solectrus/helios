class StackBuilder
  module Services
    class Postgresql < Base
      def self.service_name
        'postgresql'
      end

      def self.comment
        'Relational database for daily summaries, electricity prices, and settings'
      end

      def self.data_directories
        ['postgresql']
      end

      def to_h
        {
          image: configuration.postgresql.image,
          environment: {
            'POSTGRES_PASSWORD' => '${POSTGRES_PASSWORD}',
            'POSTGRES_DB' => 'solectrus',
          },
          volumes: ['./postgresql:/var/lib/postgresql'],
          restart: 'unless-stopped',
          healthcheck: healthcheck('CMD-SHELL', 'pg_isready -U postgres'),
        }
      end
    end
  end
end
