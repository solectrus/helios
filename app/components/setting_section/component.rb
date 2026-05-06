module SettingSection
  class Component < ViewComponent::Base
    ICONS = {
      'forecast' => 'fa-cloud-sun',
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

    def singleton_data
      @singleton_data ||= configuration.setting_data(setting)
    end

    def singleton_configured?
      singleton_data.present?
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

    # In collectors_only mode the local InfluxDB target is typically
    # write-only or unreachable for reads — values live on the remote
    # dashboard host.
    def show_dashboard_hint?
      configuration.collectors_only?
    end
  end
end
