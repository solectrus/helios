require 'net/http'

module InfluxDb
  # Low-level Net::HTTP plumbing shared by Client (data polling) and
  # ConnectionTest (survey validation).
  module Http
    # Connection-level failures that mean the host itself is unreachable, as
    # opposed to a per-request HTTP error. Once name resolution or the TCP
    # connect fails, callers stop instead of retrying into stacked timeouts.
    CONNECTION_ERRORS = [
      SocketError,
      Errno::ECONNREFUSED,
      Errno::EHOSTUNREACH,
      Errno::ENETUNREACH,
      Errno::ETIMEDOUT,
      Net::OpenTimeout,
      Net::ReadTimeout,
    ].freeze

    # Opens a Net::HTTP session against an InfluxDB endpoint. The caller owns
    # error handling — connection failures raise from CONNECTION_ERRORS.
    def self.start(host:, port:, schema:, open_timeout:, read_timeout:, &)
      Net::HTTP.start(
        host, port.to_i,
        use_ssl: schema == 'https',
        open_timeout:,
        read_timeout:,
        &
      )
    end
  end
end
