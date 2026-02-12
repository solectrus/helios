class ConfigurationsController < ApplicationController
  def show
    @configuration = Configuration.current
    @chapters = Chapter::NAMES
  end
end
