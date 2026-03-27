# Extends Rails health check with X-Boot-Id header for restart detection.
# Intentionally inherits from Rails::HealthController to preserve default behavior.
class HealthController < Rails::HealthController
  def show
    response.set_header('X-Boot-Id', Rails.application.config.boot_id)
    super
  end
end
