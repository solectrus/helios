module SettingSection
  class Component < ViewComponent::Base
    ICONS = {
      'forecast' => 'fa-cloud-sun',
      'deployment' => 'fa-sitemap',
      'system' => 'fa-gear',
      'dashboard' => 'fa-chart-line',
      'reverse_proxy' => 'fa-shield-halved',
      'backup' => 'fa-cloud-arrow-up',
      'senec' => 'fa-bolt',
      'mqtt' => 'fa-tower-broadcast',
      'shelly' => 'fa-plug-circle-bolt',
      'influxdb' => 'fa-database',
      'ingest' => 'fa-house-signal',
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
      ICONS[setting] || 'fa-circle-question'
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
    def singleton_configured?
      return true if %w[deployment ingest].include?(setting)

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
      return configuration.incomplete_influxdb? if setting == 'influxdb'

      configuration.incomplete_sources.include?(setting)
    end

    # Returns drill-down link metadata, or nil when the card has no follow-up
    # screen. Shelly devices only get a dedicated CRUD UI in collectors_only
    # mode; in full mode they are derived from sensor configurations and
    # edited on the Sensors screen.
    def drill_down
      case setting
      when 'mqtt'
        # In full mode, sensors set on MQTT define their own topics. The ones
        # listed here are extras the user adds explicitly — surface that.
        count_key = configuration.collectors_only? ? 'count' : 'additional_count'
        {
          path: helpers.datasources_mqtt_topics_path,
          count_text: I18n.t("datasources.mqtt_topics.inline.#{count_key}", count: configuration.mqtt_topics.size),
        }
      when 'shelly'
        return unless configuration.collectors_only?

        {
          path: helpers.datasources_shelly_devices_path,
          count_text: I18n.t('datasources.shelly_devices.inline.count', count: configuration.shelly_devices.size),
        }
      end
    end
  end
end
