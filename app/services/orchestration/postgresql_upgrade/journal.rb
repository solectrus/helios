module Orchestration
  class PostgresqlUpgrade
    # On-disk record of an upgrade in flight, so an interrupted run can be
    # picked up again.
    #
    # The upgrade is the one HELIOS operation that cannot be handed to a
    # detached sidecar: it rewrites config.yaml and compose.yaml between the
    # Docker calls, which is Ruby-side work. It therefore dies with the HELIOS
    # process — and it has a window (between emptying the data directory and
    # restoring the dump into the new cluster) where dying means the database
    # is *gone* and only the dump file still holds the data. Without a record
    # on disk, the next boot would know nothing about it: PostgreSQL would come
    # up on a freshly initialized cluster and the dashboard would start writing
    # into it.
    #
    # The journal is written before every step that changes something, so its
    # phase always describes the worst case that can be true when it is read
    # back (see PostgresqlUpgrade#recover! for what each phase implies):
    #
    #   preparing   dump being written, nothing touched yet
    #   migrating   image bumped in config/compose, cluster still intact
    #   rebuilding  data directory emptied or being refilled — the dump is the
    #               only complete copy of the data
    #   finishing   restore verified, only the stack reconcile is left
    #
    # It is deliberately not an Active Record row: the recovery has to work on
    # a boot where the stack (including HELIOS' own database) may be in any
    # state, and a plain file in the data directory is also what a support
    # bundle picks up.
    class Journal
      FILENAME = 'postgresql_upgrade.json'.freeze
      PHASES = %i[preparing migrating rebuilding finishing].freeze

      class << self
        def path
          File.join(Rails.configuration.data_path, 'helios', FILENAME)
        end

        # The journal on disk, or nil when there is none (the normal case) or
        # it is unreadable — a corrupt journal must not keep HELIOS from
        # booting; it degrades to "no interrupted upgrade known".
        def load
          data = JSON.parse(File.read(path), symbolize_names: true)
          phase = data[:phase]&.to_sym
          return nil unless PHASES.include?(phase)

          new(data)
        rescue SystemCallError, JSON::ParserError
          nil
        end

        def start!(dump_path:, previous_image:, previous_pgdata:, previous_major:, expected_tables:)
          new(
            phase: PHASES.first, dump_path:, previous_image:, previous_pgdata:,
            previous_major:, expected_tables:
          ).tap(&:save!)
        end
      end

      def initialize(data)
        @data = data
      end

      def phase = data[:phase].to_sym
      def dump_path = data[:dump_path]
      def previous_image = data[:previous_image]
      def previous_pgdata = data[:previous_pgdata]
      def previous_major = data[:previous_major]
      def expected_tables = data[:expected_tables]

      # Moves to a later phase. Written through immediately — the whole point
      # is that the file is current when the process is killed.
      def advance!(phase)
        raise ArgumentError, "unknown phase #{phase}" unless PHASES.include?(phase)

        data[:phase] = phase.to_s
        save!
      end

      def save!
        FileUtils.mkdir_p(File.dirname(self.class.path))
        File.write(self.class.path, JSON.generate(data))
      end

      def clear!
        FileUtils.rm_f(self.class.path)
      end

      private

      attr_reader :data
    end
  end
end
