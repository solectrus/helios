module Configurations
  class SettingsController < ApplicationController
    before_action :set_configuration
    before_action :validate_setting
    before_action :redirect_non_frame_requests, only: %i[new edit]

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
        normalize_fixed_source_mapping!(data)
        render SettingForm::Component.new(setting: 'sensor', sensor_name:, data:)
      else
        data = @configuration.setting_data(setting)
        render SettingForm::Component.new(setting:, data:)
      end
    end

    def create
      save_setting
      Orchestration::StackStatus.mark_config_changed!
      redirect_to redirect_target
    end

    def update
      save_setting
      Orchestration::StackStatus.mark_config_changed!
      redirect_to redirect_target
    end

    def destroy
      if sensor_setting?
        @configuration.remove_sensor(sensor_name)
      end

      Orchestration::StackStatus.mark_config_changed!
      redirect_to redirect_target
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

    def redirect_non_frame_requests
      return if turbo_frame_request?

      redirect_to redirect_target
    end

    def validate_setting
      return if sensor_setting? && sensor_name.present? && SensorRegistry.valid?(sensor_name)
      return if Configuration.valid?(setting)

      redirect_to sensors_path
    end

    def redirect_target
      return sensors_path if sensor_setting?
      return datasources_path if Configuration.source?(setting)

      advanced_path
    end

    def save_setting
      data = setting_params
      return unless data

      if sensor_setting?
        normalize_fixed_source_mapping!(data)
        @configuration.update_sensor(sensor_name, data)
      else
        persist_setting(data)
      end
    end

    # Handle the `enabled` UI flag: when false, remove the section entirely;
    # when true, strip the flag and save the remaining data.
    def persist_setting(data)
      if data.key?('enabled') && data.delete('enabled') == false
        @configuration.update(setting, {})
        return
      end

      @configuration.update(setting, data)
    end

    def setting_params
      JSON.parse(params.require(:data))
    rescue JSON::ParserError
      head(:bad_request)
      nil
    end

    # Ensure measurement/field match the collector config for fixed sources
    def normalize_fixed_source_mapping!(data)
      source = data['source'].to_s
      return unless source.in?(SensorMappingInjection::FIXED_FIELD_SOURCES)

      data['measurement'] = collector_measurement(source)
      data['field'] = SensorMappings.default_field(sensor_name, source)
    end

    def collector_measurement(source)
      @configuration.setting_data(source).measurement.presence ||
        SensorMappingInjection::DEFAULT_MEASUREMENTS[source]
    end
  end
end
