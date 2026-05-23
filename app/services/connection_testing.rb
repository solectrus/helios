# Shared plumbing for the surveys' "test connection" buttons. Each integration
# ships a `<Namespace>::ConnectionTest` service that responds to
# `call(check:, values:)` and returns a Result. New targets (MQTT, Shelly,
# SENEC, …) only need a service here plus a REGISTRY entry and a test button in
# their survey JSON — the controller and the frontend stay untouched.
module ConnectionTesting
  # `reason` is a stable symbol the controller maps to a localized message
  # (see `configurations.connection_test.*` in the locale files).
  Result = Data.define(:ok, :reason)

  # Mixed into the per-integration ConnectionTest services so each can build
  # a Result without repeating the keyword wiring.
  module ResultBuilder
    private

    def result(success, reason)
      Result.new(ok: success, reason:)
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
