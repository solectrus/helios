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

    def show_spinner?
      pending || transitioning?
    end

    def status_indicator
      if pending
        # Action was triggered, waiting for response
        helpers.tag.span(class: 'loading loading-spinner loading-xs text-primary')
      elsif status == 'starting' || status == 'restarting'
        # Container is starting up
        helpers.tag.span(class: 'loading loading-spinner loading-xs text-warning')
      elsif running? && health == 'starting'
        # Container running, healthcheck in progress - pulsing green ring
        helpers.tag.div(class: 'w-3 h-3 rounded-full border-2 border-success animate-pulse')
      else
        # Static indicator
        helpers.tag.div(class: "w-3 h-3 rounded-full #{indicator_class}")
      end
    end

    def indicator_class
      return 'bg-base-300' if status.nil?

      case status
      when 'running'
        indicator_running_class
      when 'created', 'removing'
        'border-2 border-base-content/30'
      when 'paused'
        'bg-info'
      when 'exited'
        'bg-neutral'
      else # dead or unknown
        'bg-error'
      end
    end

    def transitioning?
      return true if %w[starting restarting].include?(status)
      return true if running? && health == 'starting'

      false
    end

    def status_label
      return 'Processing...' if pending
      return 'Not created' if container.nil?
      return status.capitalize unless running?
      return 'Waiting for healthcheck...' if health == 'starting'
      return health.capitalize if health

      'Running'
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

      'bg-warning' # unhealthy
    end
  end
end
