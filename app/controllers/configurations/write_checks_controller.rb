module Configurations
  # Tells a survey, before it closes, whether another sensor, Shelly device or
  # MQTT mapping already writes into its measurement:field. Called via fetch()
  # from survey_controller.ts, like ConnectionTestsController.
  class WriteChecksController < ApplicationController
    include SurveyData
    include InfluxNameValidation

    def create
      data = survey_data
      return unless data

      render json: { message: influx_target_message(params.expect(:owner), data) }
    end
  end
end
