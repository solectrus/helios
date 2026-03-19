module Configurations
  class SettingsController < ApplicationController
    before_action :set_configuration
    before_action :validate_setting

    def new
      render SettingForm::Component.new(setting:)
    end

    def edit
      data = @configuration.setting_data(setting, name)
      render SettingForm::Component.new(setting:, name:, data:)
    end

    def create
      data = setting_params
      return unless data

      if Configuration.singleton?(setting)
        @configuration.update(setting, data)
      else
        identifier = data.delete('identifier')
        @configuration.add(setting, identifier, data)
      end

      redirect_to configuration_path
    end

    def update
      data = setting_params
      return unless data

      if Configuration.device?(setting)
        update_device(data)
      else
        @configuration.update(setting, data)
      end

      redirect_to configuration_path
    end

    def destroy
      @configuration.remove(setting, name)
      redirect_to configuration_path
    end

    private

    def setting
      params[:setting]
    end

    def name
      params[:name]
    end

    def update_device(data)
      new_identifier = data.delete('identifier')
      if new_identifier == name
        @configuration.update(setting, data, name:)
      else
        @configuration.remove(setting, name)
        @configuration.add(setting, new_identifier, data)
      end
    end

    def set_configuration
      @configuration = Configuration.current
    end

    def validate_setting
      redirect_to configuration_path unless Configuration.valid?(setting)
    end

    def setting_params
      JSON.parse(params.require(:data))
    rescue JSON::ParserError
      head(:bad_request)
      nil
    end
  end
end
