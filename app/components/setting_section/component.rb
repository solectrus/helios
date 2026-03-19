module SettingSection
  class Component < ViewComponent::Base
    ICONS = {
      'forecast' => 'fa-cloud-sun',
      'system' => 'fa-gear',
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
  end
end
