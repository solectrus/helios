module Export
  # Namespace of the per-service compose exporters.
  module Services
    # Host ports the managed stack claims for itself: the two Traefik
    # entrypoints, the HELIOS UI, the ingest endpoint and the encrypted
    # broker port. Every survey that asks for a host port keeps it off
    # them. Reserved whether or not those services run today, because they
    # can be switched on after the port is set, and a clash there stops
    # Traefik and the whole stack.
    RESERVED_HOST_PORTS = [80, 443, Helios::HOST_PORT, Ingest::PORT, Mosquitto::TLS_HOST_PORT].freeze

    # The services whose host port the user picks themselves. Each of them has
    # a survey that asks for the port, and that survey must refuse the ports
    # the other two hold.
    MOVABLE_HOST_PORT_SERVICES = [Dashboard, Influxdb, Mosquitto].freeze

    # Every host port the stack holds, except the one the asking survey is
    # about. `except` names that survey's own service, so the survey never
    # refuses the port it is currently set to.
    def self.claimed_host_ports(configuration, except:)
      RESERVED_HOST_PORTS +
        (MOVABLE_HOST_PORT_SERVICES - [except]).map { |service| service.host_port(configuration) }
    end
  end
end
