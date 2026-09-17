module ExternalInputInfo
  class Component < ViewComponent::Base
    attr_reader :configuration

    def initialize(configuration:)
      super()
      @configuration = configuration
    end

    def sensor_count
      @sensor_count ||= configuration.sensors_with_source('external').size
    end

    # Like every other source, this one stands on the screen whether or not it
    # is in use (see Configuration#offered_sources), dimmed while no sensor is
    # fed this way. It carries no switch: nothing is set up here, a sensor is
    # simply put on this source on the sensors screen, and the card says how.
    def dimmed?
      sensor_count.zero?
    end
  end
end
