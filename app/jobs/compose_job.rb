class ComposeJob < ApplicationJob
  queue_as :default

  def perform(action, service_name = nil)
    rebuild_stack
    mark_pending(action, service_name)
    remove_errored_containers if action.to_sym == :up
    clear_errors(action, service_name)
    execute_action(action.to_sym, service_name)
    # No broadcast on success — the EventsListener picks up Docker events
    # and broadcasts status updates via ServiceBroadcaster.
  rescue Compose::Runner::CommandError => e
    Rails.logger.error("ComposeJob failed: #{e.message}")
    broadcast_error(action, service_name, e)
  ensure
    clear_pending(action, service_name)
  end

  private

  def rebuild_stack
    StackBuilder.new(Configuration.current).write!
  end

  def execute_action(action, service_name)
    case action
    when :up then Compose::Runner.up
    when :down then Compose::Runner.down
    when :start then Compose::Runner.start(*Array(service_name))
    when :stop then Compose::Runner.stop(service_name)
    when :recreate then Compose::Runner.recreate(service_name)
    else raise ArgumentError, "Unknown compose action: #{action}"
    end
  end

  def broadcast_error(action, service_name, error)
    if batch_action?(action)
      broadcast_all_services_error(error)
    elsif service_name
      error_message = extract_error_details(error)
      affected_service = extract_affected_service(error) || service_name
      Compose::ServiceStore.set(affected_service, error_message)
      broadcast_service_status(affected_service, error_message:)
    end
  end

  def batch_action?(action)
    %i[up down].include?(action.to_sym)
  end

  # Remove containers that previously failed, so Docker Compose creates fresh ones.
  # Without this, 'docker compose up dashboard' would silently restart a broken
  # influxdb dependency from "Created" state — without port binding.
  def remove_errored_containers
    Compose::ServiceStore.each_key do |service_name|
      Compose::Runner.stop(service_name)
    rescue Compose::Runner::CommandError
      # Ignore — container may already be gone
    end
  end

  def mark_pending(action, service_name)
    if batch_action?(action)
      all_services.each { |s| Compose::ServiceStore.mark_pending(s.name) }
    elsif service_name
      Compose::ServiceStore.mark_pending(service_name)
    end
  end

  def clear_pending(action, service_name)
    if batch_action?(action)
      Compose::ServiceStore.clear_all_pending
    elsif service_name
      Compose::ServiceStore.clear_pending(service_name)
    end
  end

  def clear_errors(action, service_name)
    if batch_action?(action)
      Compose::ServiceStore.clear_all
    elsif service_name
      Compose::ServiceStore.clear(service_name)
    end
  end

  def broadcast_all_services_error(error)
    error_message = extract_error_details(error)
    affected_service_name = extract_affected_service(error) || extract_service_from_image(error)

    all_services.each do |compose_service|
      service_error = service_error_for(compose_service, affected_service_name, error_message)

      Compose::ServiceStore.set(compose_service.name, service_error) if service_error
      broadcast_service_status(compose_service.name, error_message: service_error)
    end
  end

  def service_error_for(compose_service, affected_service_name, error_message)
    # Show error on affected service, or on ALL services if we can't identify the culprit
    if affected_service_name.nil? || compose_service.name == affected_service_name
      error_message
    elsif compose_service.depends_on.key?(affected_service_name)
      dependency_error_message(affected_service_name)
    end
  end

  def compose_file
    @compose_file ||= Compose.load
  end

  def extract_service_from_image(error)
    output = error.stdout.to_s

    # Find which service uses the failing image mentioned in the error
    compose_file.services.each do |service|
      return service.name if output.include?(service.image.to_s)
    end

    nil
  end

  def all_services
    compose_file.services.reject(&:helios?)
  end

  def broadcast_service_status(service_name, error_message: nil)
    container = DockerHost::Container.find(service_name)
    compose_service = compose_file.services.find(service_name)

    html = ApplicationController.render(
      ServiceRow::Component.new(compose_service:, container:, error_message:, lazy: false),
      layout: false,
    )

    Turbo::StreamsChannel.broadcast_replace_to(
      'services',
      target: "service-#{service_name}",
      html:,
    )
  end

  def extract_error_details(error)
    error.stdout.to_s.lines.last&.strip.presence || 'Unknown error'
  end

  def dependency_error_message(dependency_name)
    display_name = compose_file.services.find(dependency_name)&.display_name || dependency_name
    "Blocked: #{display_name} failed to start"
  end

  # Find which service is affected by checking for known service names
  # in the container name pattern: <project>-<service>-<instance>
  def extract_affected_service(error)
    output = error.stdout.to_s

    compose_file.services.each do |service|
      return service.name if output.include?("-#{service.name}-")
    end

    nil
  end
end
