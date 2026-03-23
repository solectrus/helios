module Orchestration
  class StackStatus
    include Singleton

    def initialize
      @service_statuses = Concurrent::Map.new
      @overall = Concurrent::AtomicReference.new(:stopped)
      @initialized = Concurrent::AtomicBoolean.new(false)
      @restart_required = Concurrent::AtomicBoolean.new(false)
    end

    # Faster refresh when services are still starting up
    ACTIVE_REFRESH_INTERVAL = 5.seconds

    class << self
      delegate :overall,
               :refresh!,
               :update,
               :mark_config_changed!,
               :reset!,
               :services_settling?,
               to: :instance
    end

    def overall
      refresh! unless @initialized.true?
      @overall.get
    end

    def update(service_name, status)
      refresh! unless @initialized.true?
      @service_statuses[service_name.to_s] = status
      recompute_and_broadcast
    end

    def mark_config_changed!
      @restart_required.value = config_changed?
      recompute_and_broadcast(force: true)
    end

    def refresh!
      Orchestration::Container.invalidate_cache
      refresh_service_statuses

      @restart_required.value = config_changed?
      @initialized.make_true
      recompute_and_broadcast(force: true)
    rescue StandardError => e
      @initialized.make_true
      Rails.logger.error(
        "Orchestration::StackStatus.refresh! failed: #{e.class}: #{e.message}",
      )
    end

    def reset!
      @service_statuses.clear
      @overall.set(:stopped)
      @initialized.make_false
      @restart_required.make_false
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

    def recompute_and_broadcast(force: false)
      new_overall = compute_overall
      old_overall = @overall.get_and_set(new_overall)

      broadcast! if force || old_overall != new_overall
    end

    def compute_overall
      statuses = @service_statuses.values
      return :stopped if statuses.empty? || statuses.all?(:stopped)
      return :error if statuses.include?(:error)
      return :starting if statuses.include?(:starting)
      return :partial if statuses.include?(:stopped)
      return :restart_required if restart_required?

      :ok
    end

    def restart_required?
      @restart_required.true?
    end

    def config_changed?
      compose_path = ::Compose.path
      env_path = ::Env.path

      return false unless ::File.exist?(compose_path) && ::File.exist?(env_path)

      configuration = Configuration.current
      return false unless configuration.setup_completed?

      builder = Export::Builder.new(configuration)
      builder.compose_content != ::File.read(compose_path) ||
        builder.env_content != ::File.read(env_path)
    end

    def broadcast!
      Orchestration::StatusBarBroadcaster.new.broadcast
    rescue StandardError => e
      Rails.logger.error(
        "Orchestration::StackStatus broadcast failed: #{e.class}: #{e.message}",
      )
    end
  end
end
