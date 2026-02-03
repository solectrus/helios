class SetupsController < ApplicationController
  before_action :redirect_if_setup_completed

  def new
    @configuration = Configuration.current
  end

  def create
    @configuration = Configuration.current
    return render_error(:installation_date_required) if setup_params[:installation_date].blank?
    return render_error(:timezone_required) if setup_params[:timezone].blank?

    save_configuration
    finish_setup
    redirect_to root_path
  end

  private

  def setup_params
    params.permit(:installation_date, :timezone)
  end

  def save_configuration
    @configuration.installation_date = setup_params[:installation_date]
    @configuration.timezone = setup_params[:timezone]
    @configuration.save!
  end

  def finish_setup
    StackBuilder.new(@configuration).write!
    @configuration.complete_setup!
  end

  def render_error(key)
    flash.now[:alert] = I18n.t("flash.setup.#{key}")
    render :new, status: :unprocessable_content
  end

  def redirect_if_setup_completed
    redirect_to root_path if Configuration.current.setup_completed?
  end
end
