class RestartingController < ApplicationController
  skip_before_action :require_authentication
  # A pure status page, so no gate may lead away from it. An adopted stack
  # restarts HELIOS while the commissioning date is still missing, and the
  # waiting page has to stay on screen until the new boot id arrives.
  skip_before_action :require_commissioning
  layout false

  # `moved` says the restart takes the address with it, so the screen cannot
  # wait for HELIOS to answer where it stands. The address itself is not read
  # from the request: it comes from the configuration, so that nothing but
  # HELIOS decides where this page sends a reader.
  #
  # The screen renders for anyone, because a session cannot be relied on while
  # HELIOS restarts. The address is named to the signed-in reader alone, who is
  # the one who started the restart and the only one it concerns.
  def show
    @boot_id = params[:boot_id]
    @target = Export::HeliosEndpoint.url if params[:moved] && authenticated?
  end
end
