class DatasourcesController < ApplicationController
  def show
    @configuration = Configuration.current
  end
end
