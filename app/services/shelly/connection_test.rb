require 'net/http'
require 'uri'

module Shelly
  # Connection-test service for the Shelly surveys (see ConnectionTesting).
  # Two checks, dispatched by `call`:
  #
  # * `reachability` covers a local device on the home network. It hits the
  #   unauthenticated `/shelly` endpoint (which every Shelly generation
  #   answers with a JSON document describing the device, including whether it
  #   is password-protected) and, when a password is required, authenticates
  #   against the status endpoint — exactly like the shelly-collector.
  # * `cloud` covers Shelly Cloud access: it calls the same V2 endpoint the
  #   collector uses and confirms the server URL and authentication key.
  class ConnectionTest
    include ConnectionTesting::ResultBuilder
    include Loggable
    extend Loggable

    OPEN_TIMEOUT = 2
    READ_TIMEOUT = 5

    # Shelly Cloud V2 endpoint the collector reads device status from. Probed
    # with an empty `ids` list, so no device id is needed to validate the key.
    CLOUD_PATH = '/v2/devices/api/get'.freeze

    # Status endpoint per device generation — the same paths the
    # shelly-collector reads from. Authentication, when enabled, protects
    # these endpoints (but never `/shelly`).
    GEN1_STATUS_PATH = '/status'.freeze
    GEN2_STATUS_PATH = '/rpc/Shelly.GetStatus'.freeze

    # `values` carries the relevant survey answers keyed by their field name.
    def call(check:, values:)
      case check
      when 'reachability' then reachability(values)
      when 'cloud' then cloud(values)
      else result(false, :error)
      end
    end

    private

    def reachability(values)
      host, password = values.values_at('host', 'password')
      return result(false, :incomplete) if host.blank?

      info = device_info(probe(host, '/shelly'))
      return result(false, :shelly_not_shelly) unless info

      verify_access(host, info, password)
    rescue *ConnectionTesting::Http::PEER_RESET_ERRORS => e
      warn_and_result(e, 'host is not Shelly', :shelly_not_shelly)
    rescue *ConnectionTesting::Http::CONNECTION_ERRORS => e
      warn_and_result(e, 'unreachable', :shelly_unreachable)
    rescue StandardError => e
      warn_and_result(e, 'failed', :error)
    end

    # Parsed `/shelly` payload when the host is a Shelly, else nil. Every
    # generation answers `/shelly` unauthenticated; `mac` is the one key
    # present across Gen1 and Gen2+, so it confirms the host is an actual
    # Shelly and not some other service that happens to answer 2xx.
    def device_info(response)
      return unless response.is_a?(Net::HTTPSuccess)

      body = JSON.parse(response.body)
      body if body.is_a?(Hash) && body['mac'].present?
    rescue JSON::ParserError
      nil
    end

    def verify_access(host, info, password)
      return result(true, :shelly_reachable) unless auth_required?(info)
      return result(false, :shelly_password_required) if password.blank?

      if authenticated?(host, info, password)
        result(true, :shelly_reachable)
      else
        result(false, :shelly_unauthorized)
      end
    end

    # Gen1 devices report `auth`, Gen2+ devices report `auth_en`.
    def auth_required?(info)
      info['auth'] == true || info['auth_en'] == true
    end

    # Replays the shelly-collector's auth: an unauthenticated GET to the
    # protected status endpoint answers 401 with a challenge; the retry then
    # carries the matching Basic/Digest header.
    def authenticated?(host, info, password)
      path = info['gen'].to_i >= 2 ? GEN2_STATUS_PATH : GEN1_STATUS_PATH

      with_http(host) do |http|
        challenge = http.request(Net::HTTP::Get.new(path))
        next true if challenge.is_a?(Net::HTTPSuccess)
        next false unless challenge.is_a?(Net::HTTPUnauthorized)

        header = Shelly::Auth.authorization(
          challenge: challenge['www-authenticate'], http_method: 'GET', uri: path, password:,
        )
        next false unless header

        http.request(authorized_get(path, header)).is_a?(Net::HTTPSuccess)
      end
    end

    def authorized_get(path, header)
      Net::HTTP::Get.new(path).tap { |request| request['Authorization'] = header }
    end

    def cloud(values)
      server, auth_key = values.values_at('cloud_server', 'auth_key')
      return result(false, :incomplete) if [server, auth_key].any?(&:blank?)

      cloud_result(cloud_probe(server, auth_key))
    rescue *ConnectionTesting::Http::CONNECTION_ERRORS => e
      warn_and_result(e, 'cloud unreachable', :shelly_cloud_unreachable)
    rescue StandardError => e
      warn_and_result(e, 'cloud check failed', :error)
    end

    def cloud_result(response)
      case response
      when Net::HTTPSuccess, Net::HTTPBadRequest
        # 2xx: request accepted. 400: the empty probe body was rejected — but
        # the auth_key is validated before the body, so it is still valid.
        result(true, :shelly_cloud_reachable)
      when Net::HTTPUnauthorized, Net::HTTPForbidden
        result(false, :shelly_cloud_unauthorized)
      when Net::HTTPNotFound
        result(false, :shelly_cloud_unreachable)
      else
        result(false, :error)
      end
    end

    def cloud_probe(server, auth_key)
      uri = URI.join(with_scheme(server), CLOUD_PATH)
      uri.query = URI.encode_www_form(auth_key:)

      ConnectionTesting::Http.start(
        host: uri.host, port: uri.port, schema: uri.scheme,
        open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT
      ) do |http|
        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/json'
        request.body = { ids: [], select: ['status'] }.to_json
        http.request(request)
      end
    end

    # Shelly Cloud server URLs are entered with a scheme, but default to https
    # when the user leaves it off.
    def with_scheme(server)
      server.match?(%r{\Ahttps?://}i) ? server : "https://#{server}"
    end

    def probe(host, path)
      with_http(host) { |http| http.request(Net::HTTP::Get.new(path)) }
    end

    # Shelly devices serve their local API over plain http on the default port.
    def with_http(host, &)
      ConnectionTesting::Http.start(
        host:, port: 80, schema: 'http',
        open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT, &
      )
    end

    def warn_and_result(error, context, reason)
      logger.warn("Shelly connection test — #{context} (#{error.class}): #{error.message}")
      result(false, reason)
    end
  end
end
