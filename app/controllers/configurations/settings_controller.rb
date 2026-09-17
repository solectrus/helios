module Configurations
  class SettingsController < ApplicationController
    include SurveyData
    include SettingPersistence
    include TurboFrameOnly
    include InfluxNameValidation

    # Settings whose survey uses an `enabled` boolean to toggle the whole
    # section. The flag is stripped on save; on load we re-derive it from the
    # gating field (or from "any data present" when no gating field applies).
    # reverse_proxy and tibber are handled separately — see
    # #inject_enabled_flag!.
    ENABLED_FLAG_GATING_FIELD = {
      'backup' => nil,
      'tibber' => 'token',
    }.freeze

    before_action :set_configuration
    before_action :validate_setting
    before_action :reject_read_only_writes, only: %i[new create update destroy]
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
        inject_fixed_source_mapping!(data)
        inject_mqtt_ui_state!(data)
        render SettingForm::Component.new(setting: 'sensor', sensor_name:, data:)
      else
        data = @configuration.setting_data(setting)
        inject_enabled_flag!(data)
        inject_theme_sentinel!(data)
        render SettingForm::Component.new(setting:, data:)
      end
    end

    def create
      save_and_redirect
    end

    def update
      save_and_redirect
    end

    def destroy
      if sensor_setting?
        return if mqtt_name_still_needed?

        @configuration.remove_sensor(sensor_name)
      elsif Configuration.source?(setting)
        # The card offers the switch only where it can be thrown, so a request
        # for a source something reads through is a crafted one.
        return head(:forbidden) unless @configuration.source_droppable?(setting)

        @configuration.drop_source!(setting)
      end

      Orchestration::StackStatus.mark_config_changed!
      redirect_to redirect_target
    end

    private

    # A refused save has already responded, so nothing is marked and no second
    # redirect is attempted.
    def save_and_redirect
      save_setting
      return if performed?

      finish_setting_save!
      redirect_to redirect_target
    end

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

    # Read-only pseudo-settings (see Configuration::READ_ONLY_SETTINGS) render
    # the survey in display mode; the surrounding form has no Save button. A
    # crafted POST/PATCH/DELETE bypasses the UI, so refuse it here before
    # Configuration#update raises.
    def reject_read_only_writes
      return unless Configuration::READ_ONLY_SETTINGS.include?(setting)

      head :forbidden
    end

    def redirect_target
      return sensors_path if sensor_setting?
      return datasources_path if Configuration.source?(setting)
      return backups_path if setting.in?(%w[backup backup_schedule])

      settings_path
    end

    # Every path that saves nothing has already responded, so the caller checks
    # `performed?` rather than a return value of its own.
    def save_setting
      data = survey_data
      return unless data

      sensor_setting? ? save_sensor(data) : save_section(data)
      return if performed?

      # Re-anchor the schedule so the next run is the next occurrence of the
      # chosen time (today if still ahead, tomorrow if already passed) rather
      # than an immediate catch-up.
      BackupScheduler.reschedule! if setting == 'backup_schedule'
    end

    def save_sensor(data)
      return if mqtt_name_still_needed?(data['mqtt_name'])

      # After stripping: a fixed source stores no names at all, so only what
      # actually gets stored is judged.
      strip_fixed_source_mapping!(data)
      return if invalid_influx_name?(data, redirect_target)

      @configuration.update_sensor(sensor_name, data)
      @configuration.auto_enable_senec_sensors! if data['source'] == 'senec'
    end

    def save_section(data)
      return if loopback_app_host?(data)
      return if unknown_proxy_network?(data)

      persist_setting(data)
    end

    # A network name nothing on this host answers to. Compose refuses to start
    # the stack over such a network, and the services the proxy routes publish
    # no host port to fall back on, HELIOS among them. Refused here, where the
    # name is typed and the screen is still there to say so (see
    # Orchestration::ProxyNetwork).
    def unknown_proxy_network?(data)
      name = Orchestration::ProxyNetwork.missing_name(data['proxy_network'])
      return false unless name

      flash[:alert] = t('configurations.errors.unknown_proxy_network', network: name)
      redirect_to redirect_target
      true
    end

    # An address that names the machine to whoever asks would send a device or
    # a browser somewhere else back to itself. HELIOS refuses to adopt such a
    # host from the browser (see Configuration#adopt_request_host!) and the
    # connection test rejects one, but typed by hand it went through. Every
    # address derived from it was then wrong: the link to the dashboard, the
    # endpoint external sources write to, the address devices publish to.
    #
    # Leaving the field empty stays allowed. Every caller falls back to the
    # port alone, which at least works from the machine itself.
    def loopback_app_host?(data)
      host = data['app_host']
      return false unless host.present? && HostAddress.loopback?(host)

      flash[:alert] = t('configurations.errors.loopback_host', host:)
      redirect_to redirect_target
      true
    end

    # A formula reads an MQTT mapping by its MAPPING_X_NAME. Dropping that name
    # leaves a reference that no mapping defines, and mqtt-collector refuses to
    # start on it, saying so in its own log alone.
    #
    # Renaming is fine, Configuration carries the new name into the formulas.
    # Only losing the name outright is refused, and the survey keeps the field
    # mandatory for the one case it can see. It cannot cover the other two:
    # switching the sensor to another source, which drops the MQTT section as a
    # whole, and disabling the sensor.
    def mqtt_name_still_needed?(next_name = nil)
      current = @configuration.sensor_config(sensor_name).mqtt_name
      return false if current.blank? || next_name.present?

      dependents = Mqtt::MappingGraph.new(@configuration).dependents_of(current)
      return false if dependents.empty?

      flash[:alert] = t('sensors.errors.mqtt_name_in_use', names: dependents.join(', '))
      redirect_to redirect_target
      true
    end

    # A fixed source dictates measurement and field, and its form never asks
    # for them, so a saved sensor stores neither. Storing them froze a copy of
    # what was right at the time of the save: a later change to the
    # measurement of the collector left that one sensor reading the old one,
    # while every sensor without a copy followed along.
    #
    # A payload can still carry the names, from an older form or from a
    # request nothing typed, so they go before the sensor is written.
    def strip_fixed_source_mapping!(data)
      return unless fixed_source?(data['source'])

      data.delete('measurement')
      data.delete('field')
    end

    # The form shows what the collector dictates, which is what the sensor
    # reads, although the sensor stores neither (see #strip_fixed_source_mapping!).
    def inject_fixed_source_mapping!(data)
      return unless fixed_source?(data['source'])

      data['measurement'] = collector_measurement(data['source'].to_s)
      data['field'] = SensorMappings.default_field(sensor_name, data['source'].to_s)
    end

    def fixed_source?(source)
      source.to_s.in?(SensorMappings::FIXED_SOURCES)
    end

    # Re-inject the UI-only `enabled` flag for sections that use it.
    # The flag is stripped on save (see persist_setting), so it must be
    # derived from persisted state. With a gating field, `enabled` reflects
    # whether that field is set; otherwise, any persisted data flips it on.
    def inject_enabled_flag!(data)
      return if data.blank?

      return inject_reverse_proxy_ui_state!(data) if setting == 'reverse_proxy'

      # The prices survey spans two sections: `enabled` comes from the gating
      # field below (the Tibber token), but `charging` governs the separate
      # senec_charger section, which this data doesn't carry.
      data['charging'] = @configuration.senec_charger_enabled? if setting == 'tibber'

      return unless ENABLED_FLAG_GATING_FIELD.key?(setting)

      gating = ENABLED_FLAG_GATING_FIELD[setting]
      data['enabled'] = gating ? data[gating].present? : true
    end

    # The address form asks two questions nothing stores: the mode, which an
    # empty section answers with "none", and how an external proxy reaches the
    # stack, which the stored network name answers on its own. Both are derived
    # here and dropped again on save (see
    # SettingPersistence#persist_reverse_proxy).
    def inject_reverse_proxy_ui_state!(data)
      data['mode'] = data['mode'].presence || 'none'
      data['proxy_transport'] = data['proxy_network'].present? ? 'network' : 'ports'
    end

    # The "user-selectable" theme is stored as an empty string (the dashboard's
    # UI_THEME convention), but SurveyJS can't preselect a radio option with an
    # empty value. The survey uses a `user` sentinel instead: inject it on load
    # when no theme is fixed, and translate it back to `''` on save.
    def inject_theme_sentinel!(data)
      return unless setting == 'dashboard_theme'

      data['ui_theme'] = 'user' if data['ui_theme'].blank?
    end

    # Derive UI-only state (kind, extraction mode, formula of a calculated
    # sensor) from persisted MQTT fields. These keys are stripped by
    # sanitize_sensor_data on save, so they never touch config.yaml.
    def inject_mqtt_ui_state!(data)
      return unless data['source'] == 'mqtt'

      data.merge!(Surveys::MqttFields.ui_state(data, prefix: 'mqtt_', method_field: 'mqtt_extraction_mode'))
    end

    def collector_measurement(source)
      @configuration.setting_data(source).measurement.presence ||
        SensorMappings::DEFAULT_MEASUREMENTS[source]
    end
  end
end
