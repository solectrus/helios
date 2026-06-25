module Orchestration
  class StackStatus
    include Singleton
    include Loggable

    def initialize
      @service_statuses = Concurrent::Map.new
      @overall = Concurrent::AtomicReference.new(:stopped)
      @initialized = Concurrent::AtomicBoolean.new(false)
      @stopping = Concurrent::AtomicBoolean.new(false)
      @starting = Concurrent::AtomicBoolean.new(false)
    end

    class << self
      delegate :overall,
               :service_counts,
               :pending_restart_services,
               :refresh!,
               :status_for,
               :update,
               :mark_config_changed!,
               :mark_starting!,
               :mark_stopping!,
               :reset!,
               :services_settling?,
               to: :instance
    end

    def overall
      refresh! unless @initialized.true?
      @overall.get
    end

    def service_counts
      refresh! unless @initialized.true?
      statuses = @service_statuses.values
      total = statuses.size
      running = statuses.count { |s| s != :stopped }
      { running:, total: }
    end

    def pending_restart_services
      AffectedServices.compute
    end

    # Cached effective_status of a single service (:ok / :starting / :error /
    # :stopped), or nil when the service is unknown. Reads the same map that
    # backs the service counts, so callers avoid a fresh Docker lookup.
    def status_for(service_name)
      refresh! unless @initialized.true?
      @service_statuses[service_name.to_s]
    end

    def update(service_name, status)
      refresh! unless @initialized.true?
      @service_statuses[service_name.to_s] = status
      recompute_and_broadcast
    end

    def mark_config_changed!
      # Establish the baseline from the *current* (pre-change) compose before
      # rebuild_stack overwrites it, so the change is measured against the old
      # state instead of being swallowed by the lazy seed in AffectedServices.
      AffectedServices.seed_baseline_if_missing!
      rebuild_stack
      AffectedServices.invalidate_config_hashes
      recompute_and_broadcast(force: true)
    end

    def mark_starting!
      @starting.make_true
      @overall.set(compute_overall)
    end

    def mark_stopping!
      @stopping.make_true
      @overall.set(compute_overall)
    end

    def refresh!
      Orchestration::Container.invalidate_cache
      AffectedServices.invalidate_config_hashes
      refresh_service_statuses

      @initialized.make_true
      recompute_and_broadcast(force: true)
    rescue StandardError => e
      @initialized.make_true
      logger.error(
        "refresh! failed: #{e.class}: #{e.message}",
      )
    end

    def reset!
      @service_statuses.clear
      @overall.set(:stopped)
      @initialized.make_false
      @starting.make_false
      @stopping.make_false
      AffectedServices.invalidate_config_hashes
    end

    # True when services are in a transient state (:starting)
    # and need more frequent polling to catch status changes.
    def services_settling?
      @service_statuses.value?(:starting)
    end

    private

    def refresh_service_statuses
      compose_services = ::Compose.load.services.reject(&:helios?)
      containers_by_name = Orchestration::Container.all.index_by(&:service_name)

      @service_statuses.clear
      compose_services.each do |cs|
        container = containers_by_name[cs.name]
        @service_statuses[cs.name] = container&.effective_status || :stopped
      end
    end

    def rebuild_stack
      Rails.application.executor.wrap do
        configuration = Configuration.current
        return unless configuration.setup_completed?

        Export::Builder.new(configuration).write!
      end
    end

    def recompute_and_broadcast(force: false)
      @starting.make_false unless services_starting?
      new_overall = compute_overall
      @stopping.make_false if new_overall == :stopped
      old_overall = @overall.get_and_set(new_overall)

      broadcast! if force || old_overall != new_overall
    end

    # @starting must survive between two consecutive single-service starts:
    # ComposeJob#ensure clears its own PendingOperation and calls refresh!
    # *before* the next queued job has registered a :starting status, so
    # without checking pending start-like ops the flag would drop and the
    # bar would flicker through :partial.
    def services_starting?
      services_settling? || PendingOperations.any_start_pending?
    end

    def compute_overall
      statuses = @service_statuses.values
      return :stopped if statuses.empty? || statuses.all?(:stopped)
      return :stopping if stopping?
      return :error if statuses.include?(:error)
      return :starting if any_starting?(statuses)
      return :partial if statuses.include?(:stopped)
      return :restart_required if restart_required?

      :ok
    end

    def any_starting?(statuses)
      statuses.include?(:starting) || @starting.true?
    end

    def stopping?
      @stopping.true?
    end

    def restart_required?
      AffectedServices.compute.any?
    end

    def broadcast!
      Orchestration::StatusBarBroadcaster.new.broadcast
    rescue StandardError => e
      logger.error(
        "broadcast failed: #{e.class}: #{e.message}",
      )
    end
  end
end
