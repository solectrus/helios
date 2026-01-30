module StatusBadge
  class Component < ViewComponent::Base
    attr_reader :container, :pending

    def initialize(container:, pending: false)
      super()
      @container = container
      @pending = pending
    end

    def label
      return 'Processing...' if pending
      return 'Not created' if container.nil?
      return container.status.capitalize unless container.running?
      return container.health_status.capitalize if container.health_status

      'Running'
    end
  end
end
