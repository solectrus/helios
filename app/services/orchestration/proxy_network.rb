module Orchestration
  # Answers whether the Docker network the configuration names is there.
  #
  # HELIOS declares that network as one another stack owns (see
  # Export::Compose#add_networks), so compose refuses to start the whole stack
  # while it is missing:
  #
  #   network edge declared as external, but could not be found
  #
  # That refusal costs more than a failed start. The routed services publish no
  # host port on that network, HELIOS among them, so the run that fails is the
  # one that hands port 3999 over (see SelfPorts), and the interface that would
  # name the mistake goes down with it. Only a hand-edited compose.yaml brings
  # it back.
  #
  # So the name is checked twice: where it is typed, and again before a start
  # carries HELIOS itself. The network can go away between the two, because the
  # stack that owns it is not this one.
  class ProxyNetwork
    class << self
      # The configured name when Docker says it has no such network, nil
      # otherwise. Nil is also the answer while Docker does not answer at all:
      # a missing network is a fact to act on, and a daemon out of reach is
      # not that fact (see DockerCli.network_names).
      def missing(configuration = Configuration.current)
        name = configuration.reverse_proxy_network
        return if name.blank?

        missing_name(name)
      end

      # The same question for a name the user has just typed, before anything
      # of it is stored.
      def missing_name(name)
        return if name.blank?

        name if DockerCli.network_names&.exclude?(name)
      end
    end
  end
end
