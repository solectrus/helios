module SurveyField
  # The SurveyJS mount point: names the survey to load, the values to
  # preselect and the form whose submission carries the answers. The form
  # around it differs per screen (the settings modal, the commissioning
  # page), the wiring does not.
  class Component < ViewComponent::Base
    def initialize(setting:, form_id:, sensor_name: nil, data: nil)
      super()
      @setting = setting
      @form_id = form_id
      @sensor_name = sensor_name
      @data = data
    end

    attr_reader :form_id

    def survey_url
      if @setting == 'sensor'
        helpers.configuration_survey_path('sensor', format: :json, sensor: @sensor_name)
      else
        helpers.configuration_survey_path(@setting, format: :json)
      end
    end

    def initial_data_json
      @data.presence&.to_json || '{}'
    end
  end
end
