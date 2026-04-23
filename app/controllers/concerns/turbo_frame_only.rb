module TurboFrameOnly
  extend ActiveSupport::Concern

  private

  # Redirect non-turbo-frame GET/HEAD requests to `fallback`, so browsers
  # can't land on a frame-only URL after a reload. Other verbs pass through.
  def redirect_unless_turbo_frame(fallback)
    return unless request.get? || request.head?
    return if turbo_frame_request?

    redirect_to fallback
  end
end
