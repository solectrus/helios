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

    def status
      container&.status
    end

    def public_port
      container&.public_port || compose_service.public_port
    end

    def status_value
      return 'pending' if pending
      return 'running' if running?

      'stopped'
    end

    # Basic status indicator without health check (used for initial render)
    def basic_status_indicator_class
      return 'loading loading-spinner loading-xs text-primary' if pending
      if status_starting?
        return 'loading loading-spinner loading-xs text-warning'
      end

      dot = 'inline-block w-3 h-3 rounded-full'
      return "#{dot} bg-error" if error?

      "#{dot} #{basic_indicator_class}"
    end

    # Basic status label without health check (used for initial render)
    def basic_status_label
      return 'Processing...' if pending
      return error_message if error?
      return 'Not created' if container.nil?
      return status&.capitalize || 'Unknown' unless running?

      'Running'
    end

    def status_starting?
      %w[starting restarting].include?(status)
    end

    def basic_tooltip_class
      base = 'tooltip tooltip-left before:text-left before:text-xs'
      error? ? "#{base} tooltip-error" : "#{base} tooltip-info"
    end

    private

    def basic_indicator_class
      return 'border-2 border-dashed border-base-content/30' if status.nil?

      case status
      when 'running'
        'bg-success'
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

    public

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
      # Optimistic: enable if running (health will be checked lazy)
      !pending && running?
    end

    def start_disabled?
      pending || running?
    end

    def stop_disabled?
      pending || !running?
    end

    def recreate_disabled?
      pending || !running?
    end
  end
end
