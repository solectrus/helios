module Configurations
  # JSON probe endpoint for the "test connection" buttons in the surveys.
  # Called via fetch() from survey_controller.ts, so — unlike the other
  # configuration controllers — it is not a Turbo navigation. The actual probe
  # is dispatched by `target` to a registered service (see ConnectionTesting).
  class ConnectionTestsController < ApplicationController
    # The first-start page asks for the address of an external InfluxDB before
    # any other screen opens, and that survey carries the test buttons (see
    # CommissioningController). Behind the gate the fetch would follow a redirect to
    # /commissioning and parse HTML as JSON.
    skip_before_action :require_commissioning

    def create
      result = ConnectionTesting.run(
        target: params.expect(:target),
        check: params.expect(:check),
        values: probe_values,
      )
      render json: {
        ok: result.ok,
        state: result.state,
        message: t("configurations.connection_test.#{result.reason}", **result.args),
      }
    end

    private

    # The submitted survey answers, keyed by field name. They only feed an
    # outbound HTTP probe (no model assignment), so the dynamic key set is
    # taken as-is — each tester picks the fields it needs.
    def probe_values
      raw = params[:values]
      return {} unless raw.respond_to?(:to_unsafe_h)

      raw.to_unsafe_h.transform_values { |value| value.to_s.strip }
    end
  end
end
