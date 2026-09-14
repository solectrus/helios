class SettingsController < ApplicationController
  def show
    @configuration = Configuration.current
  end
end
