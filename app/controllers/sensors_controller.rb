class SensorsController < ApplicationController
  include SensorReadings

  before_action :redirect_in_collectors_only

  def show
    @configuration = Configuration.current
    @readings = fetch_readings(configuration: @configuration)
  end

  private

  def redirect_in_collectors_only
    redirect_to datasources_path if Configuration.current.collectors_only?
  end
end
