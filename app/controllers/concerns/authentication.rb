module Authentication
  extend ActiveSupport::Concern

  private

  def authorized?
    !password_required? || authenticated?
  end

  def password_required?
    admin_password.present?
  end

  def admin_password
    Configuration.current.system.admin_password
  end

  def authenticated?
    session[:authenticated] == true
  end
end
