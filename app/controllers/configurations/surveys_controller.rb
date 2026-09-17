module Configurations
  class SurveysController < ApplicationController
    # The first-start page asks for the basics before any configuration
    # exists, and it fetches its survey from here (see CommissioningController).
    skip_before_action :require_commissioning

    def show
      survey = Surveys::Builder.new(setting: params[:id], sensor_name: params[:sensor], index: params[:index]).call

      if survey
        render json: survey
      else
        head :not_found
      end
    end
  end
end
