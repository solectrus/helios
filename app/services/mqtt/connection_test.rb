module Mqtt
  # Connection-test service for the MQTT survey (see ConnectionTesting).
  # Two checks, dispatched by `call`:
  #
  # * `reachability` only confirms the host accepts a connection on the MQTT
  #   port. It runs on the survey's connection page, before any credentials
  #   are entered, so it cannot perform a full MQTT handshake yet.
  # * `credentials` connects with the supplied username/password and inspects
  #   the CONNACK return code.
  class ConnectionTest
    include ConnectionTesting::ResultBuilder

    DEFAULT_PORT = 1883
    DEFAULT_SSL_PORT = 8883

    # CONNACK return codes that mean the broker rejected the credentials
    # (4 = bad username or password, 5 = not authorized).
    AUTH_FAILURE_CODES = [4, 5].freeze

    # `values` carries the relevant survey answers keyed by their field name.
    def call(check:, values:)
      case check
      when 'reachability' then reachability(values)
      when 'credentials' then credentials(values)
      else result(false, :error)
      end
    end

    private

    def reachability(values)
      return result(false, :incomplete) if values['mqtt_host'].blank?

      if probe(values).reachable?
        result(true, :mqtt_reachable)
      else
        result(false, :mqtt_unreachable)
      end
    rescue StandardError => e
      Rails.logger.warn("MQTT reachability check failed: #{e.message}")
      result(false, :error)
    end

    def credentials(values)
      host, username, password = values.values_at('mqtt_host', 'mqtt_username', 'mqtt_password')
      return result(false, :incomplete) if host.blank? || username.blank?

      credentials_result(probe(values).connect(username:, password:))
    rescue Mqtt::Probe::ConnectionClosed
      # Reachability already proved the host is up, so a broker that drops the
      # connection mid-handshake is almost always rejecting the credentials.
      result(false, :mqtt_unauthorized)
    rescue Mqtt::Probe::NotABroker
      result(false, :mqtt_not_broker)
    rescue *Mqtt::Probe::CONNECTION_ERRORS
      result(false, :mqtt_unreachable)
    rescue StandardError => e
      Rails.logger.warn("MQTT credentials check failed: #{e.message}")
      result(false, :error)
    end

    def credentials_result(return_code)
      if return_code.zero?
        result(true, :mqtt_credentials_valid)
      elsif AUTH_FAILURE_CODES.include?(return_code)
        result(false, :mqtt_unauthorized)
      else
        result(false, :error)
      end
    end

    def probe(values)
      ssl = values['mqtt_ssl'] == 'true'
      Mqtt::Probe.new(host: values['mqtt_host'], port: port(values, ssl:), ssl:)
    end

    def port(values, ssl:)
      values['mqtt_port'].presence || (ssl ? DEFAULT_SSL_PORT : DEFAULT_PORT)
    end
  end
end
