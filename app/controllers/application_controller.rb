class ApplicationController < ActionController::Base
  include Authentication

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  before_action :require_authentication
  before_action :require_consent
  before_action :set_locale
  before_action :set_time_zone

  helper_method :authorized?, :password_required?, :config_yaml_exists?, :preferences

  private

  def require_consent
    return if config_yaml_exists?
    return unless existing_stack_files?

    redirect_to start_path
  end

  def config_yaml_exists?
    File.exist?(Configuration.path)
  end

  def existing_stack_files?
    File.exist?(Compose.path) && File.exist?(Env.path)
  end

  def require_authentication
    return if authorized?
    return if sessions_controller?

    redirect_to new_session_path
  end

  def sessions_controller?
    is_a?(SessionsController)
  end

  def preferences
    Current.preferences ||= UserPreferences.new(cookies)
  end

  def set_locale
    I18n.locale = preferences.resolved_locale(request.headers['Accept-Language'])
  end

  def set_time_zone
    tz = Configuration.current.system.timezone
    Time.zone = tz if tz.present?
  end

  def require_expert_mode
    redirect_to services_path unless preferences.expert_mode?
  end
end
