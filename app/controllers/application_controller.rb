class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  before_action :require_setup
  before_action :require_authentication

  helper_method :authenticated?

  private

  def require_setup
    return if admin_setup_completed?
    return if setup_controller?

    redirect_to new_admin_path
  end

  def require_authentication
    return unless admin_setup_completed?
    return if authenticated?
    return if sessions_controller?

    redirect_to new_session_path
  end

  def admin_setup_completed?
    @admin_setup_completed ||= Admin.exists?
  end

  def authenticated?
    session[:authenticated] == true
  end

  def setup_controller?
    is_a?(AdminsController)
  end

  def sessions_controller?
    is_a?(SessionsController)
  end
end
