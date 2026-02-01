module ServiceVersion
  class Component < ViewComponent::Base
    attr_reader :service_name, :version

    def initialize(service_name:, version:)
      super()
      @service_name = service_name
      @version = version
    end

    def frame_id
      "service-#{service_name}-version"
    end
  end
end
