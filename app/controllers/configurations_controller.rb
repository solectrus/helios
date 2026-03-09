class ConfigurationsController < ApplicationController
  def show
    @configuration = Configuration.current
  end
end
