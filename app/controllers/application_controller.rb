class ApplicationController < ActionController::Base
  include Authentication

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  before_action :require_authentication
  before_action :require_consent
  before_action :set_locale
  before_action :set_time_zone

  helper_method :authorized?, :password_required?, :show_app_chrome?, :preferences

  private

  # Whether to render the app chrome (header, mobile dock, status bar). Shown on
  # every authenticated page — including the setup flow — so navigation and stack
  # status stay reachable. Login and the /start import-consent page are
  # deliberate full-screen gates and stay bare.
  def show_app_chrome?
    authorized? && !is_a?(SessionsController) && !is_a?(StartsController)
  end

  def require_consent
    return if config_yaml_exists?
    return unless existing_stack_files?

    redirect_to start_path
  end

  def config_yaml_exists?
    File.exist?(Configuration.path)
  end

  def existing_stack_files?
    return false unless File.exist?(Compose.path) && File.exist?(Env.path)

    # A fresh install via bootstrap/install.sh creates a compose.yaml that
    # only declares the helios service — there is nothing to import yet.
    services = YAML.safe_load_file(Compose.path)&.dig('services')
    services.present? && services.keys != ['helios']
  rescue Psych::Exception
    false
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
end
