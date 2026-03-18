module Configurations
  class SurveysController < ApplicationController
    def show
      unless Chapter.valid_kind?(survey_kind)
        return head(:not_found)
      end

      path = Rails.root.join("config/surveys/#{survey_kind}.json")
      return head(:not_found) unless path.exist?

      survey = JSON.parse(path.read)
      inject_device_questions!(survey) if Chapter.device_kind?(survey_kind)
      render json: survey
    end

    private

    def survey_kind
      params[:id]
    end

    def inject_device_questions!(survey)
      survey['pages'].first['elements'].unshift(name_question, identifier_question)
    end

    def name_question
      {
        'type' => 'text',
        'name' => 'name',
        'title' => { 'de' => 'Name', 'default' => 'Name' },
        'description' => {
          'de' => 'Frei wählbarer Anzeigename für dieses Gerät',
          'default' => 'Display name for this device',
        },
        'isRequired' => true,
        'placeholder' => { 'de' => 'z.B. Geschirrspüler', 'default' => 'e.g. Dish washer' },
      }
    end

    def identifier_question
      {
        'type' => 'text',
        'name' => 'identifier',
        'title' => { 'de' => 'Kennung', 'default' => 'Identifier' },
        'description' => {
          'de' => 'Eindeutige technische Kennung (nur Kleinbuchstaben, Ziffern, Bindestriche)',
          'default' => 'Unique technical identifier (lowercase letters, digits, hyphens only)',
        },
        'isRequired' => true,
        'placeholder' => { 'de' => 'z.B. dish-washer', 'default' => 'e.g. dish-washer' },
        'validators' => [identifier_validator],
      }
    end

    def identifier_validator
      {
        'type' => 'regex',
        'text' => {
          'de' => 'Nur Kleinbuchstaben, Ziffern und Bindestriche erlaubt',
          'default' => 'Only lowercase letters, digits, and hyphens allowed',
        },
        'regex' => '^[a-z0-9][a-z0-9-]*$',
      }
    end
  end
end
