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
      tag_name, css_class = status_indicator_config
      helpers.tag.public_send(tag_name, class: css_class)
    end

    def status_indicator_config
      return [:span, 'loading loading-spinner loading-xs text-primary'] if pending
      return [:span, 'loading loading-spinner loading-xs text-warning'] if status_starting?
      return [:div, 'w-3 h-3 rounded-full border-2 border-success animate-pulse'] if healthcheck_starting?

      [:div, "w-3 h-3 rounded-full #{indicator_class}"]
    end

    def status_starting?
      %w[starting restarting].include?(status)
    end

    def healthcheck_starting?
      running? && health == 'starting'
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
      status_starting? || healthcheck_starting?
    end

    def status_label
      return 'Processing...' if pending
      return 'Not created' if container.nil?
      return status.capitalize unless running?
      return 'Waiting for healthcheck...' if health == 'starting'
      return health.capitalize if health

      'Running'
    end

    delegate :helios?, to: :compose_service

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
