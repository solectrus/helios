module SettingForm
  class Component < ViewComponent::Base
    attr_reader :setting, :name, :data

    def initialize(setting:, name: nil, data: nil)
      super()
      @setting = setting
      @name = name
      @data = data
    end

    def new_record?
      name.nil?
    end

    def form_url
      if new_record?
        helpers.configuration_settings_path
      else
        helpers.configuration_setting_path(setting:, name:)
      end
    end

    def form_method
      new_record? ? :post : :patch
    end

    def survey_url
      helpers.configuration_survey_path(setting, format: :json)
    end

    def setting_data_json
      return '{}' if new_record? || data.blank?

      json_data = data.dup
      # Inject identifier (= YAML key) back into form data for editing
      json_data['identifier'] = name if Configuration.device?(setting)
      json_data.to_json
    end
  end
end
