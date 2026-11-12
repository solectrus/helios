module Authentication
  extend ActiveSupport::Concern

  def self.password_fingerprint(password)
    OpenSSL::HMAC.hexdigest('SHA256', Rails.application.key_generator.generate_key('password_fingerprint'),
                            password.to_s)
  end

  private

  def authorized?
    !password_required? || authenticated?
  end

  def password_required?
    admin_password.present?
  end

  def admin_password
    Configuration.current.system.admin_password.presence || ENV['ADMIN_PASSWORD'].presence
  end

  # A session only counts while the password it was opened with is still the
  # current one, so changing the password signs out every other browser.
  def authenticated?
    ActiveSupport::SecurityUtils.secure_compare(session[:password_fingerprint].to_s, password_fingerprint)
  end

  def remember_authentication
    session[:password_fingerprint] = password_fingerprint
  end

  def password_fingerprint
    Authentication.password_fingerprint(admin_password)
  end
end
