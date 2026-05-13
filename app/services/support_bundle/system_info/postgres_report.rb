require 'open3'

module SupportBundle
  module SystemInfo
    # Lists every public-schema table in the SOLECTRUS PostgreSQL database
    # together with its row count. Talks to the running `postgresql` container
    # via `docker exec psql` — same pattern as ContainerLogs / BackupRunner —
    # so the report works without an Active Record connection from HELIOS.
    module PostgresReport
      module_function

      DATABASE = 'solectrus_production'.freeze
      POSTGRES_USER = 'postgres'.freeze
      SERVICE = 'postgresql'.freeze

      # Exact COUNT(*) per table in a single round-trip. `query_to_xml`
      # evaluates the dynamic count inside SQL; `pg_stat_user_tables.n_live_tup`
      # would be cheaper but is an estimate and reads 0 for never-analyzed
      # tables, which would mislead during early-install diagnostics.
      QUERY = <<~SQL.squish.freeze
        SELECT c.relname,
               (xpath('/row/c/text()',
                      query_to_xml(format('SELECT count(*) AS c FROM %I.%I', n.nspname, c.relname),
                                   false, true, '')))[1]::text::bigint
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE c.relkind = 'r' AND n.nspname = 'public'
        ORDER BY c.relname
      SQL

      def tables
        container = Orchestration::Container.find(SERVICE)
        return 'PostgreSQL container not found.' unless container
        return 'PostgreSQL container not running.' unless container.running?

        output, status = run_psql(container.name)
        return "failed (exit #{status.exitstatus}): #{output.strip}" unless status.success?

        rows = parse(output)
        return "No tables found in #{DATABASE}." if rows.empty?

        OutputFormatter.render_table(%w[TABLE ROWS], rows)
      rescue StandardError => e
        "unavailable: #{e.class}: #{e.message}"
      end

      # PGPASSWORD comes from config.yaml so we don't depend on the postgres
      # image's default `trust` rule for local-socket connections — psql still
      # works if the user has customized pg_hba.conf.
      def run_psql(container_name)
        Open3.capture2e(
          'docker', 'exec', *password_env, container_name,
          'psql', '-U', POSTGRES_USER, '-d', DATABASE,
          '-t', '-A', '-F', '|', '-c', QUERY
        )
      end

      def password_env
        password = Configuration.current.postgresql&.password
        return [] if password.blank?

        ['-e', "PGPASSWORD=#{password}"]
      end

      def parse(output)
        output.each_line.filter_map do |line|
          name, count = line.strip.split('|', 2)
          next if name.blank?

          [name, count.to_s]
        end
      end
    end
  end
end
