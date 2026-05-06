module ShellyDeviceForm
  class Component < ViewComponent::Base
    attr_reader :index, :data

    def initialize(index: nil, data: nil)
      super()
      @index = index
      @data = data
    end

    def new_record?
      index.nil?
    end

    def form_url
      if new_record?
        helpers.datasources_shelly_devices_path
      else
        helpers.datasources_shelly_device_path(index)
      end
    end

    def form_method
      new_record? ? :post : :patch
    end

    def survey_url
      helpers.configuration_survey_path('shelly_device', format: :json)
    end

    def setting_data_json
      return '{}' if new_record? || data.blank?

      data.to_json
    end
  end
end
