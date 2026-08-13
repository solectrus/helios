module Configurations
  class SurveysController < ApplicationController
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
