module Configurations
  class SettingsController < ApplicationController
    include TurboFrameOnly

    # Settings whose survey uses an `enabled` boolean to toggle the whole section.
    # The flag is stripped on save, so we re-inject it on load when data is present.
    ENABLED_FLAG_SETTINGS = %w[reverse_proxy backup].freeze

    before_action :set_configuration
    before_action :validate_setting
    before_action :require_turbo_frame, only: %i[new edit]

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
        inject_mqtt_ui_state!(data)
        render SettingForm::Component.new(setting: 'sensor', sensor_name:, data:)
      else
        data = @configuration.setting_data(setting)
        inject_enabled_flag!(data)
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

    def require_turbo_frame
      redirect_unless_turbo_frame(redirect_target)
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
        @configuration.auto_enable_senec_sensors! if data['source'] == 'senec'
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

    # Re-inject the UI-only `enabled` flag for sections that use it.
    # The flag is stripped on save (see persist_setting), so it must be derived
    # from whether the section has persisted data.
    def inject_enabled_flag!(data)
      return unless ENABLED_FLAG_SETTINGS.include?(setting) && data.present?

      data['enabled'] = true
    end

    # Derive UI-only state (extraction mode) from persisted MQTT fields.
    # This key is stripped by sanitize_sensor_data on save, so it never touches config.yaml.
    def inject_mqtt_ui_state!(data)
      return unless data['source'] == 'mqtt'

      data['mqtt_extraction_mode'] = mqtt_extraction_mode_from(data)
    end

    def mqtt_extraction_mode_from(data)
      return 'json_key' if data['mqtt_json_key'].present?
      return 'json_path' if data['mqtt_json_path'].present?
      return 'json_formula' if data['mqtt_json_formula'].present?
      return 'formula' if data['mqtt_formula'].present?

      'plain'
    end

    def collector_measurement(source)
      @configuration.setting_data(source).measurement.presence ||
        SensorMappingInjection::DEFAULT_MEASUREMENTS[source]
    end
  end
end
