module Surveys
  # Resolves the requested setting name to its concrete Survey class via
  # naming convention — no registry to maintain.
  class Builder
    def initialize(setting:, sensor_name: nil, index: nil)
      @setting = setting
      @sensor_name = sensor_name
      @index = index
    end

    def call
      klass = lookup
      return nil unless klass

      klass.new(sensor_name: @sensor_name, index: @index).call
    end

    private

    # The `< Base` gate prevents unrelated constants under `Surveys::*` from
    # being reachable via the URL.
    def lookup
      klass = "Surveys::#{@setting.to_s.camelize}::Survey".safe_constantize
      klass if klass.is_a?(Class) && klass < Base
    end
  end
end
