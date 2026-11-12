class SessionsController < ApplicationController
  skip_before_action :require_authentication
  skip_before_action :require_commissioning
  before_action :require_password

  LOGIN_ATTEMPTS = ActiveSupport::Cache::MemoryStore.new

  # Keyed on the direct peer, not on `request.remote_ip`: that one trusts any
  # X-Forwarded-For from a private address, so a client on the LAN could pick
  # a fresh address for every attempt.
  rate_limit to: 10, within: 3.minutes, only: :create,
             by: -> { request.remote_addr },
             store: LOGIN_ATTEMPTS,
             with: -> { reject_attempt(:too_many_attempts, :too_many_requests) }

  def new
    redirect_to root_path if authenticated?
  end

  def create
    if valid_password?(params[:password])
      reset_session
      remember_authentication
      redirect_to root_path
    else
      reject_attempt(:invalid_password, :unprocessable_content)
    end
  end

  def destroy
    reset_session
    redirect_to new_session_path
  end

  private

  def reject_attempt(message, status)
    flash.now[:alert] = I18n.t(message, scope: 'flash.session')
    render :new, status:
  end

  def require_password
    redirect_to root_path unless password_required?
  end

  def valid_password?(password)
    ActiveSupport::SecurityUtils.secure_compare(
      password.to_s,
      admin_password,
    )
  end
end
