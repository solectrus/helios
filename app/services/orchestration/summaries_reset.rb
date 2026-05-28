require 'open3'

module Orchestration
  # Resets the SOLECTRUS `summaries` table on the running PostgreSQL
  # container. `summary_values` rows are removed via ON DELETE CASCADE.
  #
  # SOLECTRUS caches daily aggregates here; after a bulk historical
  # import (or a restore) those rows are stale for the imported range
  # and SOLECTRUS rebuilds them on demand from the raw points, so
  # wiping is the official reset path.
  #
  # Two modes:
  #   `dates: nil` → TRUNCATE the whole table (used after a full restore
  #                  or when a CSV upload's date range cannot be inferred
  #                  from filenames).
  #   `dates: [Date, …]` → DELETE only the supplied days, so summaries
  #                  outside the imported range stay cached.
  #
  # Shells out via `docker exec` (rather than the docker-api
  # Container#exec) so PGPASSWORD can be passed in — psql via local
  # socket otherwise relies on the postgres image's default `trust`
  # rule, which breaks if the user has customized pg_hba.conf. Same
  # pattern as SupportBundle::SystemInfo::PostgresReport.
  class SummariesReset
    SERVICE = 'postgresql'.freeze
    POSTGRES_USER = 'postgres'.freeze
    POSTGRES_DATABASE = 'solectrus_production'.freeze
    TRUNCATE_SQL = 'TRUNCATE TABLE summaries CASCADE'.freeze

    def self.call(dates: nil, container: nil)
      new(dates: dates, container: container).call
    end

    def initialize(dates: nil, container: nil)
      @dates = Array(dates).presence
      @container = container || Orchestration::Container.find(SERVICE)
    end

    def call
      return false unless container&.running?

      output, status = run_psql
      return true if status.success?

      Rails.logger.warn(
        "[Orchestration::SummariesReset] failed (exit #{status.exitstatus}): #{output.strip}",
      )
      false
    rescue StandardError => e
      Rails.logger.warn("[Orchestration::SummariesReset] failed: #{e.class}: #{e.message}")
      false
    end

    private

    attr_reader :container, :dates

    # Dates are folded into contiguous ranges and emitted as OR'd
    # BETWEEN clauses so the planner can do a single index range scan
    # per range instead of N point lookups (typical SENEC year upload
    # = one range of 365 days → one BETWEEN). Date#iso8601 only emits
    # YYYY-MM-DD digits + hyphens, so the literal substitution has no
    # quoting hazard.
    def sql
      return TRUNCATE_SQL if dates.nil?

      clauses = contiguous_ranges.map do |first, last|
        "date BETWEEN '#{first.iso8601}' AND '#{last.iso8601}'"
      end
      "DELETE FROM summaries WHERE #{clauses.join(' OR ')}"
    end

    # Groups dates into [first, last] tuples of contiguous runs (day N
    # and day N+1 collapse into the same run; gaps split it). Single-day
    # uploads collapse to `[date, date]`, which `BETWEEN x AND x`
    # accepts. Dedup + sort defensively so callers can hand in arbitrary
    # date lists.
    def contiguous_ranges
      dates.uniq.sort.each_with_object([]) do |date, acc|
        if acc.last && date == acc.last[1] + 1
          acc.last[1] = date
        else
          acc << [date, date]
        end
      end
    end

    def run_psql
      Rails.logger.info(
        "[#{self.class.name}] docker exec #{container.name} psql -c #{sql.inspect}",
      )
      Open3.capture2e(
        'docker', 'exec', *password_env, container.name,
        'psql', '-v', 'ON_ERROR_STOP=1', '-U', POSTGRES_USER, '-d', POSTGRES_DATABASE,
        '-c', sql
      )
    end

    def password_env
      password = Configuration.current.postgresql&.password
      return [] if password.blank?

      ['-e', "PGPASSWORD=#{password}"]
    end
  end
end
