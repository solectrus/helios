require 'net/http'
require 'uri'

module InfluxDb
  # Connection-test service for the InfluxDB survey (see ConnectionTesting).
  # Two checks, dispatched by `call`:
  #
  # * `reachability` hits the unauthenticated `/ping` endpoint — it answers
  #   only "is there an InfluxDB at this protocol/host/port?".
  # * `credentials` sends an *empty* write request. InfluxDB authenticates the
  #   token and resolves org/bucket before it parses the request body, so an
  #   empty body coming back as 400 still proves token + org + bucket are
  #   valid — without writing a single point into the user's bucket.
  class ConnectionTest
    include ConnectionTesting::ResultBuilder
    include Loggable
    extend Loggable

    OPEN_TIMEOUT = 2
    READ_TIMEOUT = 5

    # `values` carries the relevant survey answers keyed by their field name.
    def call(check:, values:)
      case check
      when 'reachability' then reachability(values)
      when 'credentials' then credentials(values)
      else result(false, :error)
      end
    end

    private

    # `/ping` (not `/health`): it needs no auth, and — unlike `/health` —
    # works on InfluxDB Cloud as well as self-hosted OSS.
    def reachability(values)
      schema, host, port = values.values_at('schema', 'host', 'port')
      return result(false, :incomplete) if [schema, host, port].any?(&:blank?)

      response = http_get(schema, host, port, '/ping')
      influxdb_ping?(response) ? result(true, :reachable) : result(false, :not_influxdb)
    rescue *InfluxDb::Http::CONNECTION_ERRORS
      result(false, :unreachable)
    rescue StandardError => e
      logger.warn("InfluxDB reachability check failed: #{e.message}")
      result(false, :error)
    end

    def credentials(values)
      schema, host, port, org, bucket, token =
        values.values_at('schema', 'host', 'port', 'org', 'bucket', 'token_write')
      return result(false, :incomplete) if [schema, host, port, org, bucket, token].any?(&:blank?)

      credentials_result(write_probe(schema, host, port, org, bucket, token))
    rescue *InfluxDb::Http::CONNECTION_ERRORS
      result(false, :unreachable)
    rescue StandardError => e
      logger.warn("InfluxDB credentials check failed: #{e.message}")
      result(false, :error)
    end

    def credentials_result(response)
      case response
      when Net::HTTPSuccess, Net::HTTPBadRequest
        # 2xx: empty write accepted. 400: body rejected as malformed line
        # protocol — but the token and org/bucket were validated first, which
        # is exactly what this check confirms.
        result(true, :credentials_valid)
      when Net::HTTPUnauthorized, Net::HTTPForbidden
        result(false, :unauthorized)
      when Net::HTTPNotFound
        result(false, :not_found)
      else
        result(false, :error)
      end
    end

    # `/ping` answers 204 with no body; the X-Influxdb-* version headers are
    # what confirm the host is an actual InfluxDB and not some other service
    # that happens to answer 2xx.
    def influxdb_ping?(response)
      return false unless response.is_a?(Net::HTTPSuccess)

      response['x-influxdb-version'].present? || response['x-influxdb-build'].present?
    end

    def http_get(schema, host, port, path)
      with_http(schema, host, port) { |http| http.request(Net::HTTP::Get.new(path)) }
    end

    def write_probe(schema, host, port, org, bucket, token) # rubocop:disable Metrics/ParameterLists
      uri = URI("#{schema}://#{host}:#{port}/api/v2/write")
      uri.query = URI.encode_www_form(org:, bucket:)

      with_http(schema, host, port) do |http|
        request = Net::HTTP::Post.new(uri)
        request['Authorization'] = "Token #{token}"
        request['Content-Type'] = 'text/plain; charset=utf-8'
        request.body = ''
        http.request(request)
      end
    end

    def with_http(schema, host, port, &)
      InfluxDb::Http.start(host:, port:, schema:, open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT, &)
    end
  end
end
