class SensorsController < ApplicationController
  include SensorReadings

  before_action :redirect_in_collectors_only

  def show
    @configuration = Configuration.current
    # Skip the Docker inspect + InfluxDB query on the initial shell render;
    # only the lazy content frame loads readings. The SensorTable's polling
    # keeps them fresh afterwards either way.
    @readings =
      if rendering_content_frame?('configuration-content')
        fetch_readings(configuration: @configuration)
      else
        {}
      end
  end

  private

  def redirect_in_collectors_only
    redirect_to datasources_path if Configuration.current.collectors_only?
  end
end
