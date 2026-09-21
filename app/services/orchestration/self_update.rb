module Orchestration
  # Self-update: pull the new HELIOS image, then recreate the container from a
  # temporary helper container that outlives the restart (see DetachedCompose).
  #
  # Only HELIOS is recreated. The rest of the stack keeps running, including
  # services the user stopped on purpose, which a run over every service would
  # bring back up.
  class SelfUpdate
    SERVICE = Runner::SELF_SERVICE

    def self.call
      Runner.pull(service: SERVICE)
      DetachedCompose.up(services: [SERVICE], force_recreate: true, prune_images: true)
    end
  end
end
