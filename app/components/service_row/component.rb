module ServiceRow
  class Component < ViewComponent::Base
    attr_reader :compose_service, :container, :host, :pending, :error_message

    def initialize(
      compose_service:,
      container:,
      host:,
      pending: false,
      error_message: nil
    )
      super()
      @compose_service = compose_service
      @container = container
      @host = host
      @pending = pending
      @error_message = error_message
    end

    def error?
      error_message.present?
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

    def status_indicator_class
      return 'loading loading-spinner loading-xs text-primary' if pending
      return 'loading loading-spinner loading-xs text-warning' if status_starting?

      dot = 'inline-block w-3 h-3 rounded-full'
      return "#{dot} bg-error" if error?
      return "#{dot} border-2 border-success animate-pulse" if healthcheck_starting?

      "#{dot} #{indicator_class}"
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
      return error_message if error?
      return 'Not created' if container.nil?
      return status.capitalize unless running?
      return 'Waiting for healthcheck...' if health == 'starting'
      return health.capitalize if health

      'Running'
    end

    def tooltip_class
      base = 'tooltip tooltip-left before:text-left before:text-xs'

      error? ? "#{base} tooltip-error" : "#{base} tooltip-info"
    end

    delegate :helios?, to: :compose_service

    def row_class
      base = 'rounded-lg border border-base-300 p-4 shadow-sm transition-shadow'

      if helios?
        "#{base} bg-base-300 mb-6"
      else
        "#{base} bg-base-100 hover:shadow-md"
      end
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
