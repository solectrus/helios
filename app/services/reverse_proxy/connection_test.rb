require 'net/http'
require 'socket'

module ReverseProxy
  # Connection-test service for the "Address & domain" survey (see
  # ConnectionTesting). One check, `domain`, answers the question the built-in
  # Traefik depends on: does this domain lead to this machine?
  #
  # It has to be answered before the mode is saved, not after. The built-in
  # Traefik routes HELIOS itself, so a domain that leads somewhere else takes
  # the screen the user is standing on with it, and only a hand-edited
  # compose.yaml brings it back.
  #
  # Two steps, and the second one has two shapes:
  #
  # 1. Resolve the name. Nothing behind it is the common mistake (a typo, a
  #    record not created yet), and it is answered for certain.
  # 2. Prove the address leads here. While HELIOS publishes its own host port,
  #    the probe asks the domain for HELIOS's health endpoint and compares the
  #    boot id it answers with against its own — a round trip that proves the
  #    domain reaches this very process. Behind a Traefik the port carries a
  #    host rule for the domain already configured, so a request for any other
  #    name is refused before it reaches HELIOS. The probe then compares the
  #    addresses of the two names instead, which answers the same question for
  #    a stack that moves from one subdomain to the next.
  #
  # A failing step 2 is a question, not a verdict: the round trip leaves the
  # machine and comes back, which a router that does not answer its own public
  # address (no NAT loopback) blocks although the domain is right.
  class ConnectionTest
    include ConnectionTesting::ResultBuilder
    include Loggable

    OPEN_TIMEOUT = 2
    READ_TIMEOUT = 5

    # The port HELIOS publishes for itself, and the endpoint that names the
    # running process. HealthController answers it with X-Boot-Id.
    PORT = Export::Services::Helios::HOST_PORT
    PATH = '/up'.freeze
    BOOT_ID_HEADER = 'x-boot-id'.freeze

    def call(check:, values:)
      case check
      when 'domain' then domain(values)
      else result(false, :error)
      end
    end

    private

    def domain(values)
      host = HostAddress.normalize(values['app_host'])
      return result(false, :incomplete) if host.blank?

      addresses = resolve(host)
      return result(false, :domain_unresolved, host:) if addresses.empty?

      verify(host, addresses)
    rescue StandardError => e
      logger.warn("Domain check failed: #{e.message}")
      result(false, :error)
    end

    # The two shapes of step 2. Which one applies is decided by the stack that
    # runs now, not by the mode the form is about to store.
    def verify(host, addresses)
      if traefik_running?
        compare_with_current(host, addresses)
      else
        round_trip(host, addresses)
      end
    end

    def round_trip(host, addresses)
      return result(true, :domain_leads_here) if helios_answers_at?(host)

      elsewhere(addresses)
    end

    # Behind a Traefik, two names that resolve to the same address reach the
    # same machine. The name configured now is the one the user is looking at
    # HELIOS through, so it stands for this machine.
    def compare_with_current(host, addresses)
      current = configuration.public_host
      if current.blank? || current == host
        return result(false, :domain_unverified, warning: true, address: addresses.first)
      end

      if addresses.intersect?(resolve(current))
        result(true, :domain_same_server, current:)
      else
        elsewhere(addresses)
      end
    end

    # The domain leads somewhere this HELIOS did not answer from. Said as a
    # question, not as a verdict: the round trip leaves the machine and has to
    # come back, which a router that does not answer its own public address (no
    # NAT loopback) blocks although the domain is right.
    def elsewhere(addresses)
      result(false, :domain_elsewhere, warning: true, address: addresses.first)
    end

    def resolve(host)
      Addrinfo.getaddrinfo(host, nil, nil, :STREAM).map(&:ip_address).uniq
    rescue SocketError, ArgumentError
      []
    end

    # A request that leaves the machine for the domain and has to arrive back
    # at this process. The boot id is minted per start, so no other HELIOS can
    # answer with it.
    #
    # Both schemes are tried: the port carries plain HTTP while HELIOS
    # publishes it itself, and the certificate is not verified because the
    # answer that counts is a header of our own, not the identity of the peer.
    def helios_answers_at?(host)
      %w[http https].any? { |schema| boot_id_at(schema, host) == Rails.application.config.boot_id }
    end

    def boot_id_at(schema, host)
      response = ConnectionTesting::Http.start(
        host:, port: PORT, schema:, open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT, verify: false,
      ) { |http| http.request(Net::HTTP::Get.new(PATH)) }

      response[BOOT_ID_HEADER]
    rescue *ConnectionTesting::Http::CONNECTION_ERRORS
      nil
    end

    def traefik_running?
      Export::Services::Traefik.enabled?(configuration)
    end

    def configuration
      @configuration ||= Configuration.current
    end
  end
end
