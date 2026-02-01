module ServiceStatus
  class Component < ViewComponent::Base
    attr_reader :service_name, :container

    def initialize(service_name:, container:)
      super()
      @service_name = service_name
      @container = container
    end

    def frame_id
      "service-#{service_name}-status"
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

    def status_starting?
      %w[starting restarting].include?(status)
    end

    def healthcheck_starting?
      running? && health == 'starting'
    end

    def status_indicator_class
      if status_starting?
        return 'loading loading-spinner loading-xs text-warning'
      end

      dot = 'inline-block w-3 h-3 rounded-full'
      if healthcheck_starting?
        return "#{dot} border-2 border-success animate-pulse"
      end

      "#{dot} #{indicator_class}"
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
      else
        'bg-error'
      end
    end

    def status_label
      return 'Not created' if container.nil?
      return status&.capitalize || 'Unknown' unless running?
      return 'Waiting for healthcheck...' if health == 'starting'
      return health.capitalize if health

      'Running'
    end

    private

    def indicator_running_class
      return 'bg-success' if health == 'healthy' || health.nil?

      'bg-warning'
    end
  end
end
