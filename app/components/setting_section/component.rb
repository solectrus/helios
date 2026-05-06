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

    # The deployment card always reflects an effective mode (full is the
    # implicit default), so it is treated as configured even when the section
    # is empty in config.yaml. Other cards remain "not configured" until the
    # user opens them.
    def singleton_data
      @singleton_data ||= configuration.setting_data(setting)
    end

    def singleton_configured?
      return true if setting == 'deployment'

      singleton_data.present?
    end

    def status_label
      return I18n.t("configurations.settings.deployment.modes.#{configuration.mode}") if setting == 'deployment'

      I18n.t('configurations.show.configured')
    end

    def incomplete?
      configuration.incomplete_sources.include?(setting)
    end

    def show_mqtt_topics_link?
      setting == 'mqtt'
    end

    def mqtt_topics_count
      configuration.mqtt_topics.size
    end

    # Shelly devices live as a raw list under shelly.devices and only get a
    # dedicated CRUD UI in collectors_only mode; in full mode they are
    # derived from sensor configurations and edited on the Sensors screen.
    def show_shelly_devices_link?
      setting == 'shelly' && configuration.collectors_only?
    end

    def shelly_devices_count
      configuration.shelly_devices.size
    end
  end
end
