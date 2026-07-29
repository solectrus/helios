module Orchestration
  # Everything specific to the power-splitter service: triggering a full
  # recalculation (Recalculation) and reading how far it has come (Progress).
  module PowerSplitter
    SERVICE = 'power-splitter'.freeze

    # Process-local memory shared by Recalculation and Progress:
    #
    #   triggered_at — when the user last asked for a recalculation. Lets the
    #                  UI show "recalculation running" in the seconds between
    #                  the signal and the first log line of the new run.
    #   idle         — when the log last proved that nothing is being
    #                  recalculated, so Progress can skip re-reading it for a
    #                  while (see Progress::IDLE_RECHECK).
    #
    # Rails.cache is a :memory_store in production and a :null_store in test,
    # so a Concurrent::Map is both simpler and more predictable here (same
    # approach as PendingOperations). Everything stored is a pure UI aid: a
    # HELIOS restart loses it, at worst costing one extra log read.
    class State
      STORE = Concurrent::Map.new

      # Remembered per container id so a recreated container is always read
      # again instead of inheriting the previous one's marker.
      Idle = Data.define(:container_id, :at)

      class << self
        def triggered_at = STORE[:triggered_at]

        # Clears the idle marker: the badge has to appear right after the
        # click, not once the marker happens to expire.
        def trigger!
          STORE.delete(:idle)
          STORE[:triggered_at] = Time.current
        end

        def idle?(container_id, within:)
          idle = STORE[:idle]
          idle.present? && idle.container_id == container_id && idle.at > within.ago
        end

        def mark_idle(container_id)
          STORE[:idle] = Idle.new(container_id:, at: Time.current)
        end

        def clear_all
          STORE.clear
        end
      end
    end
  end
end
