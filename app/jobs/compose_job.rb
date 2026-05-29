class ComposeJob < ApplicationJob
  queue_as :default

  def perform(action, service_name = nil)
    action = action.to_sym
    rebuild_stack if applies_config?(action)
    remove_errored_containers if action == :up
    clear_errors(action, service_name)
    execute_action(action, service_name)
    @deploy_succeeded = true
  rescue Orchestration::Runner::CommandError => e
    logger.error("ComposeJob failed: #{e.message}")
    store_errors(action, service_name, e)
  ensure
    clear_pending_operations(action, service_name)
    broadcast_results(action, service_name)
  end

  private

  def rebuild_stack
    Export::Builder.new(Configuration.current).write!
  end

  def execute_action(action, service_name)
    case action
    when :up then Orchestration::Runner.up
    when :down then Orchestration::Runner.down
    when :start then Orchestration::Runner.start(*Array(service_name))
    when :stop then Orchestration::Runner.stop(service_name)
    when :recreate then Orchestration::Runner.recreate(service_name)
    when :self_recreate then Orchestration::SelfUpdate.call
    else raise ArgumentError, "Unknown compose action: #{action}"
    end
  end

  # --- Error handling ---

  def store_errors(action, service_name, error)
    if batch_action?(action)
      store_batch_errors(error)
    elsif service_name
      affected = extract_affected_service(error) || service_name
      Orchestration::ErrorStore.set(affected, extract_error_details(error))

      if affected != service_name
        Orchestration::ErrorStore.set(
          service_name,
          dependency_error_message(affected),
        )
      end
    end
  end

  def store_batch_errors(error)
    error_message = extract_error_details(error)
    affected_service_name =
      extract_affected_service(error) || extract_service_from_image(error)

    all_services.each do |compose_service|
      service_error =
        service_error_for(compose_service, affected_service_name, error_message)
      if service_error
        Orchestration::ErrorStore.set(compose_service.name, service_error)
      end
    end
  end

  def clear_errors(action, service_name)
    if batch_action?(action)
      Orchestration::ErrorStore.clear_all
    elsif service_name
      Orchestration::ErrorStore.clear(service_name)
    end
  end

  # Clear pending operation flags before the final broadcast so the
  # broadcast renders the row with its real status (running/healthy/…),
  # not the spinner that the controller put up at click time.
  def clear_pending_operations(action, service_name)
    if batch_action?(action)
      Orchestration::PendingOperations.clear_all
    elsif service_name
      Orchestration::PendingOperations.clear(service_name)
    end
  end

  # --- Broadcasting results ---

  def broadcast_results(action, service_name)
    Orchestration::Container.invalidate_cache
    update_deployed_hashes(action)
    broadcast_affected_services(action, service_name)
    Orchestration::StackStatus.refresh!
  rescue StandardError => e
    logger.error("ComposeJob broadcast failed: #{e.class}: #{e.message}")
  end

  def update_deployed_hashes(action)
    if @deploy_succeeded && applies_config?(action)
      Orchestration::AffectedServices.store_deployed_hashes!
    else
      Orchestration::AffectedServices.invalidate_config_hashes
    end
  end

  def broadcast_affected_services(action, service_name)
    if batch_action?(action)
      all_services.each { |s| broadcast_service(s.name) }
    elsif service_name
      broadcast_service(service_name)
    end
  end

  def broadcast_service(service_name)
    container = Orchestration::Container.find(service_name)
    compose_service = compose_file.services.find(service_name)
    error_message = Orchestration::ErrorStore.get(service_name)

    Orchestration::ServiceBroadcaster.broadcast_row(
      service_name,
      container:,
      compose_service:,
      error_message:,
    )
  end

  # --- Helpers ---

  def batch_action?(action)
    %i[up down].include?(action)
  end

  # Actions that apply the current compose.yaml config to containers.
  # `stop`/`down` do not create or recreate containers, so storing
  # hashes after them would incorrectly mark pending changes as deployed.
  def applies_config?(action)
    %i[up start recreate self_recreate].include?(action)
  end

  # Remove containers that previously failed, so Docker Compose creates fresh ones.
  def remove_errored_containers
    Orchestration::ErrorStore.each_key do |service_name|
      Orchestration::Runner.stop(service_name)
    rescue Orchestration::Runner::CommandError
      nil
    end
  end

  def compose_file
    @compose_file ||= Compose.load
  end

  def all_services
    compose_file.services.reject(&:helios?)
  end

  def service_error_for(compose_service, affected_service_name, error_message)
    if affected_service_name.nil? ||
       compose_service.name == affected_service_name
      error_message
    elsif compose_service.depends_on.key?(affected_service_name)
      dependency_error_message(affected_service_name)
    end
  end

  def extract_error_details(error)
    error.stdout.to_s.lines.last&.strip.presence || 'Unknown error'
  end

  def dependency_error_message(dependency_name)
    display_name =
      compose_file.services.find(dependency_name)&.display_name ||
      dependency_name
    I18n.t('services.errors.blocked_by_dependency', dependency: display_name)
  end

  def extract_service_from_image(error)
    output = error.stdout.to_s
    compose_file.services.each do |service|
      return service.name if output.include?(service.image.to_s)
    end
    nil
  end

  def extract_affected_service(error)
    output = error.stdout.to_s.lines.grep_v(/^\s+(?:Container|Network)\s/).join

    compose_file.services.each do |service|
      return service.name if output.include?("-#{service.name}-")
    end
    nil
  end
end
