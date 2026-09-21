module Orchestration
  # Whether the next `up` has to carry HELIOS itself.
  #
  # Runner.up leaves HELIOS out, so that the process running it survives the
  # run. That holds as long as HELIOS keeps the host ports it already has. It
  # stops holding the moment those ports move, which is what choosing the
  # built-in Traefik does: Traefik binds :3999 and routes HELIOS through it,
  # and HELIOS publishes nothing of its own any more. Leaving HELIOS out then
  # leaves the old container holding :3999, and Traefik cannot bind it:
  #
  #   Bind for 0.0.0.0:3999 failed: port is already allocated
  #
  # The way back has the same shape from the other side. Traefik goes, HELIOS
  # takes :3999 again, and a run without HELIOS frees the port without binding
  # it, so nothing answers at all.
  #
  # One run over every service settles both, because compose recreates every
  # changed container before it starts any of them. SelfConverge is that run.
  class SelfPorts
    SERVICE = Runner::SELF_SERVICE

    def self.drifted?
      service = ::Compose.load.services.find(SERVICE)
      return false unless service

      container = Container.find(SERVICE)
      return false unless container

      container.published_host_ports.sort != service.published_host_ports.sort
    rescue ConnectionError
      false
    end
  end
end
