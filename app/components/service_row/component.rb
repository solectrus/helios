module ServiceRow
  class Component < ViewComponent::Base
    attr_reader :compose_service, :container, :pending, :error_message, :lazy

    def initialize(
      compose_service:,
      container:,
      pending: false,
      error_message: nil,
      lazy: true
    )
      super()
      @compose_service = compose_service
      @container = container
      @pending = pending
      @error_message = error_message
      @lazy = lazy
    end

    def dom_id
      "service-#{service_name}"
    end

    def skip_lazy_loading?
      !lazy || pending || error?
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

    def status
      container&.status
    end

    def health
      container&.health_status
    end

    def version
      container&.version
    end

    def public_port
      container&.public_port || compose_service.public_port
    end

    def status_value
      return 'pending' if pending
      return 'running' if running?

      'stopped'
    end

    def status_indicator_class
      return 'loading loading-spinner loading-xs text-primary' if pending
      return 'loading loading-spinner loading-xs text-warning' if status_starting?

      dot = 'inline-block w-3 h-3 rounded-full'
      return "#{dot} bg-error" if error?
      return "#{dot} border-2 border-success animate-pulse" if healthcheck_starting?

      "#{dot} #{indicator_class}"
    end

    def status_label
      return 'Processing...' if pending
      return error_message if error?
      return 'Not created' if container.nil?

      running? ? running_status_label : (status&.capitalize || 'Unknown')
    end

    def status_starting?
      %w[starting restarting].include?(status)
    end

    def healthcheck_starting?
      running? && health == 'starting'
    end

    def tooltip_class
      base = 'tooltip tooltip-left before:text-left before:text-xs'
      error? ? "#{base} tooltip-error" : "#{base} tooltip-info"
    end

    delegate :helios?, to: :compose_service

    def row_class
      base = 'block rounded-lg border border-base-300 p-4 shadow-sm transition-shadow'

      if helios?
        "#{base} bg-base-300 mt-6"
      else
        "#{base} bg-base-100 hover:shadow-md"
      end
    end

    def open_button_enabled?
      !pending && running? && healthy?
    end

    def healthy?
      health.nil? || health == 'healthy'
    end

    def start_disabled?
      lazy || pending || running?
    end

    def stop_disabled?
      lazy || pending || !stoppable?
    end

    def recreate_disabled?
      lazy || pending || !stoppable?
    end

    def stoppable?
      container&.stoppable?
    end

    private

    def indicator_class
      return 'border-2 border-dashed border-base-content/30' if status.nil?

      case status
      when 'running'
        indicator_running_class
      when 'created', 'removing'
        'border-2 border-base-content/30'
      when 'paused'
        'bg-info'
      when 'exited'
        'bg-neutral'
      else
        'bg-error'
      end
    end

    def indicator_running_class
      return 'bg-success' if health == 'healthy' || health.nil?

      'bg-warning'
    end

    def running_status_label
      return 'Waiting for healthcheck...' if health == 'starting'

      health&.capitalize || 'Running'
    end
  end
end
