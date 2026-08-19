module Configurations
  class SettingsController < ApplicationController
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
        normalize_fixed_source_mapping!(data)
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

      Orchestration::StackStatus.mark_config_changed!
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

      advanced_path
    end

    # Every path that saves nothing has already responded, so the caller checks
    # `performed?` rather than a return value of its own.
    def save_setting
      data = setting_params
      return unless data

      if sensor_setting?
        return if mqtt_name_still_needed?(data['mqtt_name'])

        # After normalization: a fixed source overwrites whatever names the
        # payload carried, so only what actually gets stored is judged.
        normalize_fixed_source_mapping!(data)
        return if invalid_influx_name?(data, redirect_target)

        @configuration.update_sensor(sensor_name, data)
        @configuration.auto_enable_senec_sensors! if data['source'] == 'senec'
      else
        persist_setting(data)
      end

      # Re-anchor the schedule so the next run is the next occurrence of the
      # chosen time (today if still ahead, tomorrow if already passed) rather
      # than an immediate catch-up.
      BackupScheduler.reschedule! if setting == 'backup_schedule'
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

    # Handle the `enabled` UI flag: when false, clear the section entirely;
    # when true, strip the flag and save the remaining data. Borrowed fields
    # (e.g. reverse_proxy's trusted_proxy_ranges) live in a different section,
    # so clearing this one never touches them — Configuration#update routes
    # them to their own section regardless of the toggle.
    def persist_setting(data)
      strip_theme_sentinel!(data)

      return persist_reverse_proxy(data) if setting == 'reverse_proxy'
      return persist_tibber(data) if setting == 'tibber'

      return @configuration.update(setting, {}) if data.key?('enabled') && data.delete('enabled') == false

      preserve_software_owned_image!(data)
      @configuration.update(setting, data)
    end

    # The prices survey drives two services through two UI-only flags. `enabled`
    # owns the Tibber collector (its own section), `charging` owns the SENEC
    # charger, whose fields BORROWED_FIELDS routes into `senec_charger`. Neither
    # flag is stored: whichever is off has its section's fields blanked, and
    # Configuration#update drops a section once its last field goes.
    def persist_tibber(data)
      enabled = data.delete('enabled') == true
      charging = data.delete('charging') == true

      data = {} unless enabled

      # Whether this survey run actually put the charging question on screen:
      # where the charger's dependencies don't hold, Surveys::Tibber::Survey
      # drops the charging pages server-side, so this save must not speak for
      # the charger in either direction (see #blank_senec_charger! /
      # #ignore_senec_charger!).
      if @configuration.senec_charger_configurable?
        blank_senec_charger!(data) unless enabled && charging
      else
        ignore_senec_charger!(data)
      end
      preserve_software_owned_image!(data) if enabled

      @configuration.update('tibber', data)
    end

    # Charging was offered and turned off (or the prices went with it): clear
    # the tuning. Configuration#update drops the section with its last field.
    def blank_senec_charger!(data)
      Configuration::SENEC_CHARGER_SURVEY_FIELDS.each { |field| data[field] = nil }
    end

    # Charging was never offered, so a missing `charging` flag means "not
    # asked", not "switched off". Drop the charger fields from the payload
    # instead: blanking would delete a tuning the user was never shown and
    # cannot re-enter until the dependency returns, while storing would let a
    # payload configure what the survey refused to render.
    def ignore_senec_charger!(data)
      data.except!(*Configuration::SENEC_CHARGER_SURVEY_FIELDS)
    end

    # reverse_proxy uses a tri-state `mode` (none/internal/external) instead of
    # the boolean `enabled` toggle. The mode is stored explicitly: external mode
    # has no required field of its own (bind_ip is optional), so without a
    # persisted marker it would be indistinguishable from `none` and silently
    # collapse on reload. Drop the fields that don't belong to the chosen mode
    # before saving. Borrowed fields (trusted_proxy_ranges, force_ssl) are
    # routed to their own section by Configuration#update.
    def persist_reverse_proxy(data)
      case data['mode']
      when 'external'
        data.delete('app_domain')
        data.delete('letsencrypt_email')
        @configuration.update('reverse_proxy', data)
      when 'internal'
        data.delete('bind_ip')
        # The managed Traefik terminates TLS itself, so the flag is implied and
        # the survey hides it. Blank it, or a value left over from a previous
        # mode would survive invisibly.
        data['force_ssl'] = nil
        @configuration.update('reverse_proxy', data)
      else # 'none' (or missing): clear the whole section
        # `force_ssl` survives: a proxy can terminate TLS without HELIOS
        # knowing a domain, so the survey asks for it in this mode too.
        # Configuration#update routes it into `dashboard` and empties the
        # section with what remains.
        @configuration.update('reverse_proxy', data.slice('force_ssl'))
      end
    end

    # The `image` key on per-service singletons is owned by the Software
    # survey. Per-service surveys don't ship it, but `Configuration#update`
    # replaces the whole section — so re-inject the persisted value before
    # saving to avoid dropping the user's channel choice on every edit.
    def preserve_software_owned_image!(data)
      return unless Configuration::SOFTWARE_IMAGE_OWNERS.include?(setting)
      return if data.key?('image')

      persisted = @configuration.setting_data(setting)['image']
      data['image'] = persisted if persisted.present?
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
      return unless source.in?(SensorMappings::FIXED_SOURCES)

      data['measurement'] = collector_measurement(source)
      data['field'] = SensorMappings.default_field(sensor_name, source)
    end

    # Re-inject the UI-only `enabled` flag for sections that use it.
    # The flag is stripped on save (see persist_setting), so it must be
    # derived from persisted state. With a gating field, `enabled` reflects
    # whether that field is set; otherwise, any persisted data flips it on.
    def inject_enabled_flag!(data)
      return if data.blank?

      if setting == 'reverse_proxy'
        data['mode'] = reverse_proxy_mode(data)
        return
      end

      # The prices survey spans two sections: `enabled` comes from the gating
      # field below (the Tibber token), but `charging` governs the separate
      # senec_charger section, which this data doesn't carry.
      data['charging'] = @configuration.senec_charger_enabled? if setting == 'tibber'

      return unless ENABLED_FLAG_GATING_FIELD.key?(setting)

      gating = ENABLED_FLAG_GATING_FIELD[setting]
      data['enabled'] = gating ? data[gating].present? : true
    end

    # Resolve the reverse_proxy mode for the UI radio. A persisted `mode` is the
    # source of truth; fall back to field presence for configs saved before
    # `mode` was stored and for imported stacks (a stored `app_domain` means a
    # HELIOS-managed Traefik, a stored `bind_ip` means an external one).
    def reverse_proxy_mode(data)
      return data['mode'] if data['mode'].present?
      return 'internal' if data['app_domain'].present?
      return 'external' if data['bind_ip'].present?

      'none'
    end

    # The "user-selectable" theme is stored as an empty string (the dashboard's
    # UI_THEME convention), but SurveyJS can't preselect a radio option with an
    # empty value. The survey uses a `user` sentinel instead: inject it on load
    # when no theme is fixed, and translate it back to `''` on save.
    def inject_theme_sentinel!(data)
      return unless setting == 'dashboard_theme'

      data['ui_theme'] = 'user' if data['ui_theme'].blank?
    end

    def strip_theme_sentinel!(data)
      return unless setting == 'dashboard_theme'

      data['ui_theme'] = '' if data['ui_theme'] == 'user'
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
