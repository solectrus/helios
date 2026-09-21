module Orchestration
  # Brings the whole stack in line with the compose file on disk, HELIOS
  # included. The run therefore ends the process that starts it, so it goes
  # through the helper container (see DetachedCompose).
  #
  # Only for the case SelfPorts describes: a host port that moves between
  # HELIOS and another service. Every other change is handled by Runner.up,
  # which leaves HELIOS running and keeps the screen the user is on.
  class SelfConverge
    def self.call
      # Same reason as in Runner#compose_up: compose would start a detached
      # container as-is, so it has to go before anything comes up.
      DetachedContainers.sweep

      DetachedCompose.up(remove_orphans: true)
    end
  end
end
