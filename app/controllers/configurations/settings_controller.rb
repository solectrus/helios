module Configurations
  class SettingsController < ApplicationController
    before_action :set_configuration
    before_action :validate_setting

    def new
      if sensor_setting?
        render SettingForm::Component.new(setting: 'sensor', sensor_name:)
      else
        render SettingForm::Component.new(setting:)
      end
    end

    def edit
      if sensor_setting?
        data = @configuration.sensor_config(sensor_name)
        render SettingForm::Component.new(setting: 'sensor', sensor_name:, data:)
      else
        data = @configuration.setting_data(setting)
        render SettingForm::Component.new(setting:, data:)
      end
    end

    def create
      data = setting_params
      return unless data

      if sensor_setting?
        @configuration.update_sensor(sensor_name, data)
      else
        @configuration.update(setting, data)
      end

      DockerHost::StackStatus.mark_config_changed!
      redirect_to configuration_path
    end

    def update
      data = setting_params
      return unless data

      if sensor_setting?
        @configuration.update_sensor(sensor_name, data)
      else
        @configuration.update(setting, data)
      end

      DockerHost::StackStatus.mark_config_changed!
      redirect_to configuration_path
    end

    def destroy
      if sensor_setting?
        @configuration.remove_sensor(sensor_name)
      end

      DockerHost::StackStatus.mark_config_changed!
      redirect_to configuration_path
    end

    private

    def setting
      params[:setting]
    end

    def sensor_name
      params[:name]
    end

    def sensor_setting?
      setting == 'sensor'
    end

    def set_configuration
      @configuration = Configuration.current
    end

    def validate_setting
      return if sensor_setting? && sensor_name.present? && SensorRegistry.valid?(sensor_name)
      return if Configuration.valid?(setting)

      redirect_to configuration_path
    end

    def setting_params
      JSON.parse(params.require(:data))
    rescue JSON::ParserError
      head(:bad_request)
      nil
    end
  end
end
