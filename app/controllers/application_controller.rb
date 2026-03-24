class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  before_action :auto_import_existing_config
  before_action :require_authentication
  before_action :set_locale
  before_action :set_time_zone

  helper_method :authenticated?, :preferences

  private

  def auto_import_existing_config
    return if config_yaml_exists?
    return unless existing_stack_files?

    reader = Import::StackReader.new(compose_path: Compose.path, env_path: Env.path)
    Import::ConfigurationImporter.new(reader).import!
  rescue Import::StackReader::Error
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
    return if ENV['ADMIN_PASSWORD'].blank?
    return if authenticated?
    return if sessions_controller?

    redirect_to new_session_path
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

  def set_time_zone
    tz = Configuration.current.system.timezone
    Time.zone = tz if tz.present?
  end

  def require_expert_mode
    redirect_to services_path unless preferences.expert_mode?
  end
end
