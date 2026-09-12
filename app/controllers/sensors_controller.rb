class SensorsController < ApplicationController
  include SensorReadings

  before_action :redirect_in_collectors_only

  def show
    @configuration = Configuration.current
    # Render the table shell without values and let the SensorTable's polling
    # fetch them, so the response is not blocked on the Docker inspect + N
    # sequential InfluxDB queries. The values stream in with the first poll
    # (which fires immediately on connect) instead of holding up the response.
    # Polling is gated on the local InfluxDB container being up so a stopped DB
    # does not produce a flood of connection errors.
    @polling_enabled = readings_available?(@configuration)
  end

  private

  def redirect_in_collectors_only
    redirect_to datasources_path if Configuration.current.collectors_only?
  end
end
