class AdminsController < ApplicationController
  skip_before_action :require_setup
  skip_before_action :require_authentication

  before_action :redirect_if_admin_exists

  def new; end

  def create
    return render_error(:password_blank) if params[:password].blank?
    return render_error(:passwords_mismatch) if passwords_mismatch?

    Admin.create_admin!(password: params[:password])
    session[:authenticated] = true
    redirect_to root_path
  end

  private

  def passwords_mismatch?
    params[:password] != params[:password_confirmation]
  end

  def render_error(key)
    flash.now[:alert] = I18n.t("flash.admin.#{key}")
    render :new, status: :unprocessable_content
  end

  def redirect_if_admin_exists
    redirect_to root_path if Admin.setup_completed?
  end
end
