class SupportsController < ApplicationController
  include TurboFrameOnly

  before_action :require_turbo_frame, only: :new

  def new; end

  def create
    send_data SupportBundle.build,
              filename: SupportBundle.filename,
              type: 'application/zip',
              disposition: 'attachment'
  end

  private

  def require_turbo_frame
    redirect_unless_turbo_frame(services_path)
  end
end
