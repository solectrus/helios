# Extends Rails health check with X-Boot-Id and X-Version headers
# for restart detection and version reporting.
# Intentionally inherits from Rails::HealthController to preserve default behavior.
class HealthController < Rails::HealthController
  def show
    response.set_header('X-Boot-Id', Rails.application.config.boot_id)
    response.set_header(
      'X-Version',
      Rails.application.config.x.git.commit_version,
    )
    super
  end
end
