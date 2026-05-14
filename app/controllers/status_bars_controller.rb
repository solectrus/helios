class StatusBarsController < ApplicationController
  include TurboFrameOnly

  before_action :require_turbo_frame, only: :show

  def show
    render StatusBar::Component.new, layout: false
  end

  private

  def require_turbo_frame
    redirect_unless_turbo_frame(services_path)
  end
end
