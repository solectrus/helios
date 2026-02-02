class ConfigurationsController < ApplicationController
  skip_before_action :require_authentication # TODO: Remove after development

  def show
    @configuration = Configuration.current
    @chapters = Chapter::NAMES
  end
end
