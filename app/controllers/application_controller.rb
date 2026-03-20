class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  before_action :require_setup
  before_action :auto_import_existing_config
  before_action :require_authentication
  before_action :set_locale

  helper_method :authenticated?, :preferences

  private

  def require_setup
    return if admin_setup_completed?
    return if is_a?(AdminsController)

    redirect_to new_admin_path
  end

  def auto_import_existing_config
    return if is_a?(AdminsController)
    return if config_yaml_exists?
    return unless existing_stack_files?

    reader = StackReader.new(compose_path: Compose.path, env_path: Env.path)
    ConfigurationImporter.new(reader).import!
  rescue StackReader::Error
    # If docker compose config fails (e.g., invalid YAML), skip auto-import
    nil
  end

  def config_yaml_exists?
    stack_path = Rails.configuration.helios_stack_path
    File.exist?(File.join(stack_path, Configuration::YAML_FILENAME))
  end

  def existing_stack_files?
    File.exist?(Compose.path) && File.exist?(Env.path)
  end

  def require_authentication
    return unless admin_setup_completed?
    return if authenticated?
    return if sessions_controller?

    redirect_to new_session_path
  end

  def admin_setup_completed?
    @admin_setup_completed ||= Admin.setup_completed?
  end

  def authenticated?
    session[:authenticated] == true
  end

  def sessions_controller?
    is_a?(SessionsController)
  end

  def preferences
    Current.preferences ||= UserPreferences.new(cookies)
  end

  def set_locale
    I18n.locale = preferences.locale.to_sym
  end

  def require_expert_mode
    redirect_to services_path unless preferences.expert_mode?
  end
end
