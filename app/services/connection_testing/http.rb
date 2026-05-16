require 'net/http'

module ConnectionTesting
  # Net::HTTP plumbing for the survey connection-test probes. Generic over any
  # integration that speaks HTTP (SENEC, Shelly). InfluxDB keeps its own
  # InfluxDb::Http because that module is also shared with the data-polling
  # client.
  module Http
    # Failures that mean the host itself could not be contacted, as opposed to
    # a per-request HTTP error. SSLError covers an https probe hitting a plain
    # http port; EOFError the reverse.
    CONNECTION_ERRORS = [
      SocketError,
      Errno::ECONNREFUSED,
      Errno::ECONNRESET,
      Errno::EHOSTUNREACH,
      Errno::ENETUNREACH,
      Errno::ETIMEDOUT,
      Net::OpenTimeout,
      Net::ReadTimeout,
      OpenSSL::SSL::SSLError,
      EOFError,
    ].freeze

    # The subset of CONNECTION_ERRORS that can only happen *after* the TCP
    # connection was established — the peer accepted the connection and then
    # reset or closed it. For a protocol probe this proves a host is present
    # at the address; it just doesn't speak the expected protocol.
    PEER_RESET_ERRORS = [
      Errno::ECONNRESET,
      EOFError,
    ].freeze

    # Opens a Net::HTTP session. `verify: false` accepts self-signed
    # certificates — SENEC devices ship one for their local https endpoint.
    # The caller owns error handling: connection failures raise from
    # CONNECTION_ERRORS.
    def self.start(host:, port:, schema:, open_timeout:, read_timeout:, verify: true, &) # rubocop:disable Metrics/ParameterLists
      options = { use_ssl: schema == 'https', open_timeout:, read_timeout: }
      options[:verify_mode] = OpenSSL::SSL::VERIFY_NONE unless verify

      Net::HTTP.start(host, port.to_i, **options, &)
    end
  end
end
