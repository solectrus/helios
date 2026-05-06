module ServiceRow
  class Component < ViewComponent::Base
    attr_reader :compose_service, :container, :error_message, :lazy

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

    # Combines the explicit @pending flag (set by controllers for instant
    # click feedback) with the persisted PendingOperations store so polling,
    # broadcasts and full-page reloads keep the spinner up for the whole
    # duration of a long-running compose action — not just until the next
    # render reveals the still-running old container.
    def pending
      @pending || pending_operation.present?
    end
    alias pending? pending

    def pending_operation
      return @pending_operation if defined?(@pending_operation)

      @pending_operation = Orchestration::PendingOperations.get(service_name)
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
      return 'health_starting' if healthcheck_starting?
      return 'running' if running?

      'stopped'
    end

    def status_indicator_class
      return 'loading loading-spinner loading-xs text-primary' if pending
      if status_starting?
        return 'loading loading-spinner loading-xs text-warning'
      end

      dot = 'inline-block size-4 rounded-full'
      return "#{dot} bg-error" if error?
      return "#{dot} bg-warning" if start_pending?
      if healthcheck_starting?
        return 'loading loading-spinner loading-xs text-success'
      end

      "#{dot} #{indicator_class}"
    end

    def status_label
      return pending_label if pending
      return error_message if error?
      if container.nil?
        return start_pending? ? t('.start_pending') : t('.not_created')
      end

      running? ? running_status_label : container_status_label
    end

    # Showing the running container's version while a recreate is in flight
    # is misleading — the user just clicked "Update" and still sees the old
    # version. Hide it until the operation finishes; the new version then
    # animates in via the Turbo stream broadcast.
    def show_version?
      !lazy && !pending && version.present?
    end

    def status_starting?
      %w[starting restarting].include?(status)
    end

    def healthcheck_starting?
      running? && health == 'starting'
    end

    def healthcheck_passing?
      running? && health == 'healthy' && !pending && !error?
    end

    def tooltip_class
      base = 'tooltip tooltip-left before:text-left before:text-xs'
      if error?
        "#{base} tooltip-error before:max-w-sm before:break-words"
      elsif start_pending?
        "#{base} tooltip-warning before:max-w-sm before:break-words"
      else
        "#{base} tooltip-info"
      end
    end

    delegate :helios?, to: :compose_service

    def restart_pending?
      return @restart_pending if defined?(@restart_pending)

      @restart_pending =
        !helios? && !pending &&
        Orchestration::AffectedServices.compute.include?(service_name)
    end

    def start_pending?
      return @start_pending if defined?(@start_pending)

      @start_pending =
        !helios? && !pending && container.nil? &&
        Orchestration::AffectedServices.start_pending.include?(service_name)
    end

    def row_class
      base =
        'block rounded-lg border border-base-300 p-3 sm:p-4 shadow-sm transition-shadow'

      if helios?
        "#{base} bg-base-300 mt-6"
      else
        "#{base} bg-base-100 hover:shadow-md"
      end
    end

    def open_button_enabled?
      !pending && running? && health != 'unhealthy'
    end

    def legacy_image?
      return false if helios?

      DockerImages.legacy?(service_name, compose_service.image)
    end

    # True when the running container's image hash differs from the image
    # configured in compose.yaml — typically because a mutable tag (e.g.
    # `:latest`, `:develop`, `:2-alpine`) was repulled and the container is
    # still on the previous digest. A recreate brings it onto the new image.
    # Suppressed while a legacy upgrade is offered, since recreating now
    # would only entrench the legacy tag.
    def outdated_image?
      return false if helios? || legacy_image?
      return false unless container&.running?

      compose_service.image != container.image
    end

    def recommended_image
      @recommended_image ||= DockerImages.recommended_for(service_name)
    end

    def recreate_warning?
      restart_pending? || outdated_image?
    end

    def start_disabled?
      lazy || pending || running? || incomplete_source?
    end

    def incomplete_source?
      return false unless service_name.end_with?('-collector')

      source = service_name.delete_suffix('-collector')
      Configuration.current.incomplete_sources.include?(source)
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

    def logs_available?
      return false unless container

      %w[created removing].exclude?(status)
    end

    private

    def pending_label
      return t('.processing') unless pending_operation

      t(
        ".pending_label.#{pending_operation}",
        default: t('.processing'),
      )
    end

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
      return t('.waiting_for_healthcheck') if health == 'starting'
      return t('.unhealthy') if health == 'unhealthy'
      return t('.healthy') if health == 'healthy'

      t('.running')
    end

    def container_status_label
      return t('.unknown') unless status

      t(".statuses.#{status}", default: status.capitalize)
    end
  end
end
