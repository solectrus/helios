module ServiceRow
  class Component < ViewComponent::Base
    attr_reader :compose_service, :container, :host, :pending

    def initialize(compose_service:, container:, host:, pending: false)
      super()
      @compose_service = compose_service
      @container = container
      @host = host
      @pending = pending
    end

    def service_name
      compose_service.name
    end

    def running?
      container&.running?
    end

    def health
      container&.health_status
    end

    def status
      container&.status
    end

    def public_port
      container&.public_port || compose_service.public_port
    end

    def image_version
      container&.image_version || compose_service.image_version
    end

    def status_value
      return 'pending' if pending
      return 'running' if running?

      'stopped'
    end

    def indicator_class
      return nil if pending
      return 'bg-base-300' if status.nil?
      return 'border-2 border-base-content/30' if status == 'created'
      return indicator_running_class if running?

      'bg-error'
    end

    def open_button_enabled?
      !pending && (health == 'healthy' || (running? && !health))
    end

    def start_disabled?
      pending || running?
    end

    def stop_disabled?
      pending || !running?
    end

    def restart_disabled?
      pending || !running?
    end

    private

    def indicator_running_class
      return 'bg-success' if health == 'healthy' || health.nil?

      'bg-warning'
    end
  end
end
