class ComposeJob < ApplicationJob
  queue_as :default

  def perform(action, service_name = nil)
    case action.to_sym
    when :up
      Compose::Runner.up
    when :down
      Compose::Runner.down
    when :start
      Compose::Runner.start(*Array(service_name))
    when :stop
      Compose::Runner.stop(service_name)
    when :restart
      service_name ? Compose::Runner.restart(service_name) : restart_stack
    end
  rescue Compose::Runner::CommandError => e
    Rails.logger.error("ComposeJob failed: #{e.message}")
  end

  private

  def restart_stack
    Compose::Runner.down
    Compose::Runner.up
  end
end
