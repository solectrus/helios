module SettingSection
  class Component < ViewComponent::Base
    ICONS = {
      'forecast' => 'fa-cloud-sun',
      'deployment' => 'fa-sitemap',
      'software' => 'fa-code-branch',
      'system_general' => 'fa-sliders',
      'system_network' => 'fa-network-wired',
      'system_security' => 'fa-key',
      'dashboard_co2' => 'fa-leaf',
      'dashboard_theme' => 'fa-palette',
      'dashboard_network' => 'fa-globe',
      'reverse_proxy' => 'fa-shield-halved',
      'backup' => 'fa-cloud-arrow-up',
      'senec' => 'fa-bolt',
      'tibber' => 'fa-euro-sign',
      'mqtt' => 'fa-tower-broadcast',
      'shelly' => 'fa-plug-circle-bolt',
      'influxdb' => 'fa-database',
      'ingest_settings' => 'fa-house-signal',
      'storage' => 'fa-hard-drive',
    }.freeze

    FORECAST_PROVIDERS = {
      'pvnode' => 'pvnode',
      'solcast' => 'Solcast',
      'forecast.solar' => 'Forecast.Solar',
    }.freeze

    attr_reader :setting, :configuration

    def initialize(setting:, configuration:)
      super()
      @setting = setting
      @configuration = configuration
    end

    def icon
      self.class.icon_for(setting)
    end

    def title
      I18n.t("configurations.settings.#{setting}.title")
    end

    def description
      I18n.t("configurations.settings.#{setting}.description", default: nil)
    end

    def link_path
      if singleton_configured?
        helpers.edit_configuration_setting_path(setting:, name: setting)
      else
        helpers.new_configuration_setting_path(setting:)
      end
    end

    # The deployment card always reflects an effective mode (full is the
    # implicit default), so it is treated as configured even when the section
    # is empty in config.yaml. Other cards remain "not configured" until the
    # user opens them.
    def singleton_data
      @singleton_data ||= configuration.setting_data(setting)
    end

    # Ingest, like deployment, has an effective state even when the section is
    # empty in config.yaml — defaults (image, retention_hours) kick in and the
    # service is running. Treat it as configured so the card stays green.
    #
    # The prices data carries the borrowed charger tuning, and a leftover
    # `image` alone says nothing either — only an API token means prices are
    # actually being collected.
    def singleton_configured?
      return true if %w[deployment ingest].include?(setting)
      return configuration.tibber_enabled? if setting == 'tibber'

      singleton_data.present?
    end

    def status_label
      return I18n.t("configurations.settings.deployment.modes.#{configuration.mode}") if setting == 'deployment'
      if forecast_provider_known?
        return I18n.t('configurations.show.configured_for', provider: FORECAST_PROVIDERS.fetch(singleton_data.forecast))
      end

      I18n.t('configurations.show.configured')
    end

    def status_text
      return I18n.t('configurations.show.incomplete') if incomplete?
      return status_label if singleton_configured?

      I18n.t('configurations.settings.not_configured')
    end

    def status_dot_class
      return 'bg-warning' if incomplete?
      return 'bg-success' if singleton_configured?

      'bg-base-content/30'
    end

    def status_text_class
      return 'text-warning' if incomplete?
      return 'text-base-content/70' if singleton_configured?

      'text-base-content/55'
    end

    def forecast_provider_known?
      setting == 'forecast' && FORECAST_PROVIDERS.key?(singleton_data.forecast)
    end

    def incomplete?
      configuration.setting_incomplete?(setting)
    end

    def self.icon_for(setting)
      ICONS[setting] || 'fa-circle-question'
    end

    # Returns drill-down link metadata, or nil when the card has no follow-up
    # screen. The Shelly device CRUD is reachable in collectors_only mode and,
    # in full mode, for multi-device setups where `shelly.devices` is a
    # standalone array — single-device full-mode setups derive the device from
    # the `source: shelly` sensor and are edited on the Sensors screen instead.
    def drill_down
      case setting
      when 'mqtt' then mqtt_drill_down
      when 'shelly' then shelly_drill_down
      end
    end

    private

    def mqtt_drill_down
      # In full mode, sensors set on MQTT define their own topics. The ones
      # listed here are extras the user adds explicitly — surface that.
      count_key = configuration.collectors_only? ? 'count' : 'additional_count'
      {
        path: helpers.datasources_mqtt_topics_path,
        count_text: I18n.t("datasources.mqtt_topics.inline.#{count_key}", count: configuration.mqtt_topics.size),
      }
    end

    def shelly_drill_down
      devices = configuration.shelly_devices
      return unless configuration.collectors_only? || devices.any?

      {
        path: helpers.datasources_shelly_devices_path,
        count_text: I18n.t('datasources.shelly_devices.inline.count', count: devices.size),
      }
    end
  end
end
