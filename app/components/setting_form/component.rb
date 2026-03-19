module SettingForm
  class Component < ViewComponent::Base
    attr_reader :setting, :sensor_name, :data

    def initialize(setting:, sensor_name: nil, data: nil)
      super()
      @setting = setting
      @sensor_name = sensor_name
      @data = data
    end

    def new_record?
      sensor_setting? ? data.blank? : false
    end

    def sensor_setting?
      setting == 'sensor'
    end

    def form_url
      if sensor_setting?
        if new_record?
          helpers.configuration_settings_path
        else
          helpers.configuration_setting_path(setting: 'sensor', name: sensor_name)
        end
      elsif new_record?
        helpers.configuration_settings_path
      else
        helpers.configuration_setting_path(setting:, name: setting)
      end
    end

    def form_method
      new_record? ? :post : :patch
    end

    def survey_url
      if sensor_setting?
        helpers.configuration_survey_path('sensor', format: :json, sensor: sensor_name)
      else
        helpers.configuration_survey_path(setting, format: :json)
      end
    end

    def setting_data_json
      return '{}' if new_record? || data.blank?

      data.to_json
    end

    def hidden_setting_value
      sensor_setting? ? 'sensor' : setting
    end

    def hidden_name_value
      sensor_name
    end
  end
end
