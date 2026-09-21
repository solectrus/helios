module Export
  # The address HELIOS answers on from outside, for a reader that has to leave
  # the one it is on. A converge that moves the host port of HELIOS (see
  # Orchestration::SelfPorts) takes the current address with it, and the screen
  # showing the restart would otherwise wait at an address nothing serves any
  # more.
  #
  # Behind either proxy this is the address the Open button of the HELIOS
  # service already leads to, taken from the same place, so the two cannot name
  # different addresses for one service. Without a proxy there is no such
  # address, and the published host port is the answer.
  #
  # Returns nil when nothing in the configuration names the machine. The reader
  # then stays where it is.
  class HeliosEndpoint
    PORT = Services::Helios::HOST_PORT

    def self.url(configuration = Configuration.current)
      new(configuration).url
    end

    def initialize(configuration)
      @configuration = configuration
    end

    def url
      return unless host

      PublicUrl.build(configuration, Services::Helios.service_name, published: true) ||
        "http://#{HostAddress.for_url(host)}:#{PORT}"
    end

    private

    attr_reader :configuration

    def host
      @host ||= configuration.public_host
    end
  end
end
