class AdvancedController < ApplicationController
  def show
    @configuration = Configuration.current
  end
end
