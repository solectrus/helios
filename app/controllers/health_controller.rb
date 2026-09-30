# Extends Rails health check with X-Boot-Id and X-Version headers
# for restart detection and version reporting, plus X-Action-Required
# so the SOLECTRUS dashboard can point the user to HELIOS.
# Intentionally inherits from Rails::HealthController to preserve default behavior.
class HealthController < Rails::HealthController
  # Stack states the status bar paints amber or red. :starting and :stopping
  # settle on their own and ask nothing of the user.
  ATTENTION_STATES = %i[partial error restart_required].freeze

  def show
    response.set_header('X-Boot-Id', Rails.application.config.boot_id)
    response.set_header(
      'X-Version',
      Rails.application.config.x.git.commit_version,
    )
    response.set_header('X-Action-Required', '1') if action_required?
    super
  end

  private

  # Rails::HealthController answers any exception with a 500, which the
  # dashboard reads as "no HELIOS". A failing check must only drop the header.
  def action_required?
    !Configuration.current.configuration_complete? ||
      Orchestration::StackStatus.overall.in?(ATTENTION_STATES)
  rescue StandardError => e
    logger.warn("action_required? failed: #{e.class}: #{e.message}")
    false
  end
end
