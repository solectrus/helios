class ComposeJob < ApplicationJob
  queue_as :default

  def perform(action, service_name = nil)
    execute_action(action.to_sym, service_name)
  rescue Compose::Runner::CommandError => e
    Rails.logger.error("ComposeJob failed: #{e.message}")
    broadcast_error(action, service_name, e)
  end

  private

  def execute_action(action, service_name)
    case action
    when :up then Compose::Runner.up
    when :down then Compose::Runner.down
    when :start then Compose::Runner.start(*Array(service_name))
    when :stop then Compose::Runner.stop(service_name)
    when :recreate then Compose::Runner.recreate(service_name)
    end
  end

  def broadcast_error(action, service_name, error)
    if batch_action?(action)
      broadcast_all_services_error(error)
    elsif service_name
      error_message = extract_error_details(error)
      affected_service = extract_affected_service(error) || service_name
      broadcast_service_status(affected_service, error_message:)
    end
  end

  def batch_action?(action)
    %i[up down].include?(action.to_sym)
  end

  def broadcast_all_services_error(error)
    error_message = extract_error_details(error)
    affected_service_name = extract_affected_service(error) || extract_service_from_image(error)

    all_services.each do |compose_service|
      # Show error on affected service, or on ALL services if we can't identify the culprit
      service_error = if affected_service_name.nil? || compose_service.name == affected_service_name
                        error_message
                      end
      broadcast_service_status(compose_service.name, error_message: service_error)
    end
  end

  def extract_service_from_image(error)
    output = error.stdout.to_s
    compose_file = Compose.load

    # Find which service uses the failing image mentioned in the error
    compose_file.services.each do |service|
      return service.name if output.include?(service.image.to_s)
    end

    nil
  end

  def all_services
    Compose.load.services.reject(&:helios?)
  end

  def broadcast_service_status(service_name, error_message: nil)
    container = DockerHost::Container.find(service_name)
    compose_service = Compose.load.services.find(service_name)

    html = ApplicationController.render(
      ServiceRow::Component.new(compose_service:, container:, host: 'localhost', pending: false, error_message:),
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

  # Extract service name from container name in error message
  # Container names follow the pattern: <project>-<service>-<instance>
  # Example: "/solectrus-influxdb-1" -> "influxdb"
  def extract_affected_service(error)
    output = error.stdout.to_s

    # Match container name pattern in quotes: "/<project>-<service>-<number>"
    return unless (match = output.match(%r{"/([^"]+)-(\w+)-\d+"}).presence)

    service_name = match[2]

    # Verify this service exists in our compose file
    compose_service = Compose.load.services.find(service_name)
    compose_service ? service_name : nil
  end
end
