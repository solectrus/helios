module Export
  class Env
    class Postgresql < Section
      def call
        env.add_section('PostgreSQL database')
        entry('POSTGRES_PASSWORD', configuration.postgresql.password,
              'Database password — auto-generated, do not change after first start')
        optional_entry('PGDATA', configuration.postgresql.pgdata,
                       'Postgres data directory inside the container (imported from existing installation)')
        volume_path_entry(Services::Postgresql, 'PostgreSQL data')
      end
    end
  end
end
