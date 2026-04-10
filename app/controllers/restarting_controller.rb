class RestartingController < ApplicationController
  skip_before_action :require_authentication
  layout false

  def show
    @boot_id = params[:boot_id]
  end
end
