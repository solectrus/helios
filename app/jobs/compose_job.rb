class ComposeJob < ApplicationJob
  queue_as :default

  def perform(action, service_name = nil)
    execute_action(action.to_sym, service_name)
  rescue Compose::Runner::CommandError => e
    Rails.logger.error("ComposeJob failed: #{e.message}")
    broadcast_error(service_name, e)
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

  def broadcast_error(service_name, error)
    return unless service_name

    error_message = extract_error_details(error)
    broadcast_service_status(service_name, error_message:)
  end

  def broadcast_service_status(service_name, error_message: nil)
    container = DockerHost::Container.find(service_name)
    compose_service = Compose.load.services.find(service_name)

    html = ApplicationController.render(
      ServiceRow::Component.new(compose_service:, container:, host: 'localhost', pending: false, error_message:),
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
end
