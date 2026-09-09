# Shared plumbing for the surveys' "test connection" buttons. Each integration
# ships a `<Namespace>::ConnectionTest` service that responds to
# `call(check:, values:)` and returns a Result. New targets (MQTT, Shelly,
# SENEC, …) only need a service here plus a REGISTRY entry and a test button in
# their survey JSON — the controller and the frontend stay untouched.
module ConnectionTesting
  # `reason` is a stable symbol the controller maps to a localized message
  # (see `configurations.connection_test.*` in the locale files). `args` fills
  # the placeholders of a message that names what the probe was given, such as
  # the host it could not use.
  Result = Data.define(:ok, :reason, :args) do
    def initialize(ok:, reason:, args: {}) # rubocop:disable Naming/MethodParameterName
      super
    end
  end

  # Mixed into the per-integration ConnectionTest services so each can build
  # a Result without repeating the keyword wiring.
  module ResultBuilder
    private

    def result(success, reason, **args)
      Result.new(ok: success, reason:, args:)
    end

    # A probe that could not reach its target. A collector runs in its own
    # service, where a loopback address points at that service instead of at
    # the machine or the device meant, so the address cannot work. The answer
    # then names it, in place of a generic "not reachable" the user cannot act
    # on. Classified after the attempt, not before it, so a host that does
    # answer is never refused.
    def unreachable_result(host, reason)
      return result(false, reason) unless ConnectionTesting.loopback_host?(host)

      result(false, :loopback_host, host:)
    end
  end

  # Survey `target` → connection-test service.
  REGISTRY = {
    'influxdb' => InfluxDb::ConnectionTest,
    'senec' => Senec::ConnectionTest,
    'shelly' => Shelly::ConnectionTest,
    'mqtt' => Mqtt::ConnectionTest,
    'backup' => Backups::ConnectionTest,
  }.freeze

  # Addresses that reach the calling service itself (see `unreachable_result`).
  LOOPBACK_HOSTS = ['localhost', '::1', '0.0.0.0'].freeze

  # The whole 127.0.0.0/8 range is loopback, not just 127.0.0.1.
  LOOPBACK_IPV4 = /\A127\./

  def self.loopback_host?(host)
    normalized = host.to_s.strip.downcase.delete_prefix('[').delete_suffix(']')

    LOOPBACK_HOSTS.include?(normalized) || normalized.match?(LOOPBACK_IPV4)
  end

  def self.run(target:, check:, values:)
    tester = REGISTRY[target]
    return Result.new(ok: false, reason: :error) unless tester

    tester.new.call(check:, values:)
  end
end
