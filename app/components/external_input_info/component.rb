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

    def render?
      sensor_count.positive?
    end
  end
end
