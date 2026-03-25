module Orchestration
  class StackStatus
    include Singleton

    def initialize
      @service_statuses = Concurrent::Map.new
      @overall = Concurrent::AtomicReference.new(:stopped)
      @initialized = Concurrent::AtomicBoolean.new(false)
      @restart_required = Concurrent::AtomicBoolean.new(false)
      @stopping = Concurrent::AtomicBoolean.new(false)
      @starting = Concurrent::AtomicBoolean.new(false)
    end

    class << self
      delegate :overall,
               :refresh!,
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

    def update(service_name, status)
      refresh! unless @initialized.true?
      @service_statuses[service_name.to_s] = status
      recompute_and_broadcast
    end

    def mark_config_changed!
      @restart_required.value = config_changed?
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
      @starting.make_false
      @stopping.make_false
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
      @starting.make_false unless services_settling?
      new_overall = compute_overall
      @stopping.make_false if new_overall == :stopped
      old_overall = @overall.get_and_set(new_overall)

      broadcast! if force || old_overall != new_overall
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
      @restart_required.true?
    end

    def config_changed?
      compose_path = ::Compose.path
      env_path = ::Env.path

      return false unless ::File.exist?(compose_path) && ::File.exist?(env_path)

      # Wrap in executor for DB connection management in background threads.
      # executor.wrap is reentrant, so this is safe from request threads too.
      Rails.application.executor.wrap do
        configuration = Configuration.current
        next false unless configuration.setup_completed?

        builder = Export::Builder.new(configuration)
        builder.compose_content != ::File.read(compose_path) ||
          builder.env_content != ::File.read(env_path)
      end
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
