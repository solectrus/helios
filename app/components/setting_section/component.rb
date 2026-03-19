module SettingSection
  class Component < ViewComponent::Base
    ICONS = {
      'inverter' => 'fa-solar-panel',
      'battery' => 'fa-car-battery',
      'wallbox' => 'fa-charging-station',
      'car' => 'fa-car',
      'heatpump' => 'fa-fan',
      'consumer' => 'fa-plug',
      'forecast' => 'fa-cloud-sun',
      'system' => 'fa-gear',
      'reverse_proxy' => 'fa-shield-halved',
      'backup' => 'fa-cloud-arrow-up',
      'dashboard' => 'fa-gauge-high',
      'sensors' => 'fa-gauge',
    }.freeze

    attr_reader :setting, :configuration

    def initialize(setting:, configuration:)
      super()
      @setting = setting
      @configuration = configuration
    end

    def device?
      Configuration.device?(setting)
    end

    def singleton?
      Configuration.singleton?(setting)
    end

    def icon
      ICONS[setting] || 'fa-circle-question'
    end

    def title
      I18n.t("configurations.settings.#{setting}.title")
    end

    def add_path
      helpers.new_configuration_setting_path(setting:)
    end

    def devices
      @devices ||= configuration.devices_of(setting)
    end

    def singleton_data
      @singleton_data ||= configuration.setting_data(setting)
    end

    def singleton_configured?
      singleton_data.present?
    end
  end
end
