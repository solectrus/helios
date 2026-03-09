module Configurations
  class SurveysController < ApplicationController
    def show
      unless Chapter.valid_kind?(survey_kind)
        return head(:not_found)
      end

      path = Rails.root.join("config/surveys/#{survey_kind}.json")
      return head(:not_found) unless path.exist?

      survey = JSON.parse(path.read)
      inject_name_question!(survey) if Chapter.device_kind?(survey_kind)
      render json: survey
    end

    private

    def survey_kind
      params[:id]
    end

    def inject_name_question!(survey)
      name_question = {
        'type' => 'text',
        'name' => 'name',
        'title' => { 'de' => 'Name', 'default' => 'Name' },
        'description' => {
          'de' => 'Vergib einen eindeutigen Namen für dieses Gerät',
          'default' => 'Give this device a unique name',
        },
        'isRequired' => true,
      }
      survey['pages'].first['elements'].unshift(name_question)
    end
  end
end
