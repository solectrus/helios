module ServiceRow
  class Component < ViewComponent::Base # rubocop:disable Metrics/ClassLength
    include Openable

    # Literal class names so the Tailwind v4 content scanner emits every
    # variant; `bg-#{status_color}` interpolation would drop them from the
    # build. Both maps are keyed by #status_color, the single source of truth
    # for the status color — so the dot and its tooltip always agree.
    DOT_FILL_CLASSES = {
      success: 'bg-success',
      warning: 'bg-warning',
      info: 'bg-info',
      neutral: 'bg-neutral',
      error: 'bg-error',
    }.freeze

    TOOLTIP_COLORS = {
      success: 'tooltip-success',
      warning: 'tooltip-warning',
      info: 'tooltip-info',
      neutral: 'tooltip-neutral',
      muted: 'tooltip-neutral',
      error: 'tooltip-error',
    }.freeze

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

    # Operations that bring a container up (start/recreate/upgrade) get a green
    # spinner; stop gets the same muted gray as the "not started" indicator.
    # Prevents the amber primary spinner from looking like a warning.
    def start_pending?
      Orchestration::PendingOperations::START_OPERATIONS.include?(pending_operation)
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

    def status_value
      return 'pending' if pending
      return 'health_starting' if healthcheck_starting?
      return 'running' if running?

      'stopped'
    end

    def status_indicator_class
      if pending
        color = start_pending? ? 'text-success' : 'text-base-content/30'
        return "loading loading-spinner loading-sm #{color}"
      end
      if status_starting?
        return 'loading loading-spinner loading-sm text-success'
      end

      dot = 'inline-block size-5 rounded-full'
      return "#{dot} bg-error" if error?

      "#{dot} #{indicator_class}"
    end

    def status_label
      return pending_label if pending
      return error_message if error?
      return t('.not_created') if container.nil?

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

    # Container is up but its healthcheck has not passed yet: shown as a solid
    # green circle with a dark animated ball inside, bridging the gap between the
    # start spinner and the green check mark. Pending/error states take
    # precedence (spinner/red dot).
    def healthcheck_waiting?
      healthcheck_starting? && !pending && !error?
    end

    def healthcheck_passing?
      running? && health == 'healthy' && !pending && !error?
    end

    def tooltip_class
      base = 'tooltip tooltip-right xl:tooltip-left'
      # Long error messages need to wrap and stay readable; short status
      # labels keep the default tooltip size to match the other tooltips.
      base += ' before:max-w-2xs before:text-left before:text-xs before:break-words' if error?
      "#{base} #{TOOLTIP_COLORS.fetch(status_color)}"
    end

    # Single source of truth for the status color, shared by the dot and its
    # tooltip. Precedence mirrors how the dot is rendered in the template.
    def status_color
      return :success if healthcheck_passing? || healthcheck_waiting?
      return start_pending? ? :success : :muted if pending
      return :success if status_starting?
      return :error if error?

      container_color
    end

    def container_color
      case status
      when nil, 'created', 'removing' then :muted
      when 'running' then health.in?([nil, 'healthy']) ? :success : :warning
      when 'paused' then :info
      when 'exited' then :neutral
      else :error
      end
    end

    delegate :helios?, to: :compose_service

    # Preserved (unmanaged) services like dozzle: HELIOS exports but never
    # manages them, so removal is the only configuration action offered.
    def unmanaged?
      Configuration.current.unmanaged_service?(service_name)
    end

    def restart_pending?
      return @restart_pending if defined?(@restart_pending)

      @restart_pending =
        !helios? && !pending &&
        Orchestration::AffectedServices.compute.include?(service_name)
    end

    def row_class
      base = 'block border-y border-base-content/10 p-3 sm:p-4 transition-colors duration-200 md:rounded-xl md:border'

      if helios?
        "#{base} bg-base-300/60 mt-6"
      else
        "#{base} bg-base-100 hover:border-base-content/25"
      end
    end

    # Stays disabled until the container is actually reachable: a still-running
    # healthcheck ('starting') means the service is up but not ready, so opening
    # it would likely hit a connection error or half-booted UI.
    def open_button_enabled?
      !pending && running? && (health.nil? || health == 'healthy')
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

    # Starting any service is blocked until the whole configuration is complete
    # (sources, InfluxDB target, and the mandatory installation date). Mirrors
    # the global start button and the server-side require_configuration_complete
    # guard, so the UI never offers a start that the server would reject.
    def start_disabled?
      lazy || pending || running? || !Configuration.current.configuration_complete?
    end

    # Per-row source warning (links to /datasources). Narrower than
    # start_disabled?: it flags only this collector's own incomplete source.
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

    # Service actions that reach into the container itself (exec, signal) need
    # one that is actually up and not in the middle of an operation.
    def container_actionable?
      !lazy && !pending && running?
    end

    # Flushing the cache is Redis-specific and runs `redis-cli` inside the
    # container, so it only works while Redis is running.
    def clear_cache_enabled?
      redis? && container_actionable?
    end

    def redis?
      service_name == 'redis'
    end

    def power_splitter?
      service_name == Orchestration::PowerSplitter::SERVICE
    end

    # Recalculating means signalling the running container, so it needs a
    # container that is actually up.
    def recalculation_enabled?
      power_splitter? && container_actionable?
    end

    # Snapshot of a running recalculation (nil when none is in flight).
    # Reads the container log, so it is fetched only for the one service
    # that can be recalculating at all, and never for a skeleton row.
    def recalculation
      return @recalculation if defined?(@recalculation)

      @recalculation =
        (Orchestration::PowerSplitter::Progress.call(container) if recalculation_enabled?)
    end

    def recalculating?
      recalculation.present?
    end

    # nil until the log reveals how much there is to do; the badge then shows
    # a spinner instead of a number.
    delegate :percent, to: :recalculation, prefix: true

    # A PostgreSQL major-version upgrade migrates the database via dump &
    # restore (see Orchestration::PostgresqlUpgrade) — offered while an older
    # major than the recommended image is running.
    def postgresql_upgrade_available?
      return false unless service_name == 'postgresql'
      return false if lazy || pending

      Orchestration::PostgresqlUpgrade.available?(container)
    end

    def postgresql_target_major
      Orchestration::PostgresqlUpgrade.target_major
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
      case status
      when nil
        'border-2 border-dashed border-base-content/30'
      when 'created', 'removing'
        'border-2 border-base-content/30'
      else
        DOT_FILL_CLASSES.fetch(status_color, 'bg-error')
      end
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
