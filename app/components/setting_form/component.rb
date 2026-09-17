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

    # Only a sensor can be new: every other setting has its own section in
    # config.yaml and is always updated in place.
    def form_url
      if sensor_setting?
        return helpers.configuration_settings_path if new_record?

        helpers.configuration_setting_path(setting: 'sensor', name: sensor_name)
      else
        helpers.configuration_setting_path(setting:, name: setting)
      end
    end

    def form_method
      new_record? ? :post : :patch
    end
  end
end
