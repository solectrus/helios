require 'net/http'
require 'uri'

module Senec
  # Connection-test service for the SENEC survey (see ConnectionTesting).
  # Covers local access only (SENEC.Home V2.1 / V3) — cloud access goes
  # through mein-senec.de and is not probed here.
  #
  # The probe POSTs a tiny JSON-RPC request to `/lala.cgi` — the same endpoint
  # the senec-collector reads from — and confirms the device echoes the
  # requested `ENERGY` section back. Local devices answer over https with a
  # self-signed certificate, so certificate verification is disabled.
  class ConnectionTest
    include ConnectionTesting::ResultBuilder
    include Loggable
    extend Loggable

    # SENEC devices are slow embedded boxes; allow generous timeouts so a slow
    # TLS handshake or a slow `/lala.cgi` response isn't mistaken for an
    # unreachable device.
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 10

    # Smallest request that still proves the host speaks the SENEC protocol:
    # the device echoes the section back with the value hex-encoded.
    PROBE_BODY = { 'ENERGY' => { 'STAT_STATE' => '' } }.freeze

    # `values` carries the relevant survey answers keyed by their field name.
    def call(check:, values:)
      case check
      when 'reachability' then reachability(values)
      else result(false, :error)
      end
    end

    private

    def reachability(values)
      schema, host = values.values_at('schema', 'host')
      return result(false, :incomplete) if [schema, host].any?(&:blank?)

      senec?(probe(schema, host)) ? result(true, :senec_reachable) : result(false, :senec_not_senec)
    rescue *ConnectionTesting::Http::PEER_RESET_ERRORS => e
      # The host accepted the connection, then reset it — something is there,
      # but it does not speak the SENEC protocol.
      warn_and_result(e, 'host is not SENEC', :senec_not_senec)
    rescue *ConnectionTesting::Http::CONNECTION_ERRORS => e
      warn_and_result(e, 'unreachable', :senec_unreachable)
    rescue StandardError => e
      warn_and_result(e, 'failed', :error)
    end

    def warn_and_result(error, context, reason)
      logger.warn("SENEC reachability check — #{context} (#{error.class}): #{error.message}")
      result(false, reason)
    end

    # A SENEC device answers 2xx and echoes the `ENERGY` object back — that
    # distinguishes it from some other service that happens to answer 2xx.
    def senec?(response)
      return false unless response.is_a?(Net::HTTPSuccess)

      body = JSON.parse(response.body)
      body.is_a?(Hash) && body['ENERGY'].is_a?(Hash)
    rescue JSON::ParserError
      false
    end

    def probe(schema, host)
      uri = URI("#{schema}://#{host}/lala.cgi")

      with_http(schema, host) do |http|
        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/json'
        request.body = PROBE_BODY.to_json
        http.request(request)
      end
    end

    # SENEC has no port field — the device answers on the schema's default
    # port (443 for https, 80 for http).
    def with_http(schema, host, &)
      ConnectionTesting::Http.start(
        host:, port: (schema == 'https' ? 443 : 80), schema:,
        open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT, verify: false, &
      )
    end
  end
end
