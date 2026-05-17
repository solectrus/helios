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
          volumes: [bind_mount(container_data_path)],
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

      # The PostgreSQL image's data directory moved between major versions:
      # `postgres:17` and older expose `/var/lib/postgresql/data` as the
      # image `VOLUME`, `postgres:18`+ expose the parent `/var/lib/postgresql`
      # (per-major subpath underneath, easing pg_upgrade). Bind-mount whichever
      # the running image expects so the data directory lines up without a
      # PGDATA override — see ADR-0003.
      def container_data_path
        major = configuration.postgresql.image.to_s[/postgres:(\d+)/, 1]&.to_i
        major && major <= 17 ? '/var/lib/postgresql/data' : '/var/lib/postgresql'
      end
    end
  end
end
