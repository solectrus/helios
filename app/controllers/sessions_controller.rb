class SessionsController < ApplicationController
  skip_before_action :require_authentication

  def new
    redirect_to root_path if authenticated?
  end

  def create
    if valid_password?(params[:password])
      session[:authenticated] = true
      redirect_to root_path
    else
      flash.now[:alert] = I18n.t('flash.session.invalid_password')
      render :new, status: :unprocessable_content
    end
  end

  def destroy
    reset_session
    redirect_to new_session_path
  end

  private

  def valid_password?(password)
    ActiveSupport::SecurityUtils.secure_compare(
      password.to_s,
      ENV.fetch('ADMIN_PASSWORD'),
    )
  end
end
