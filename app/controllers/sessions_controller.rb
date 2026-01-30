class SessionsController < ApplicationController
  skip_before_action :require_authentication

  def new
    redirect_to root_path if authenticated?
  end

  def create
    admin = Admin.current
    if admin&.authenticate(params[:password])
      session[:authenticated] = true
      redirect_to root_path
    else
      flash.now[:alert] = I18n.t('flash.session.invalid_password')
      render :new, status: :unprocessable_content
    end
  end

  def destroy
    session[:authenticated] = false
    redirect_to new_session_path
  end
end
