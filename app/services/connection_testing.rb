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
      return result(false, reason) unless Loopback.host?(host)

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

  def self.run(target:, check:, values:)
    tester = REGISTRY[target]
    return Result.new(ok: false, reason: :error) unless tester

    tester.new.call(check:, values:)
  end
end
