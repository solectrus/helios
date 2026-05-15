module SettingLink
  # Chip-style entry for the Advanced page: icon + label, plus a warning dot
  # when the setting is `incomplete?`. Used for every setting in every group;
  # SettingSection (the full card) is reserved for the Datasources page where
  # status and counts carry more meaning per item.
  class Component < ViewComponent::Base
    def initialize(setting:, configuration:)
      super()
      @setting = setting
      @configuration = configuration
    end

    def icon
      SettingSection::Component.icon_for(@setting)
    end

    def title
      I18n.t("configurations.settings.#{@setting}.title")
    end

    def link_path
      if configured?
        helpers.edit_configuration_setting_path(setting: @setting, name: @setting)
      else
        helpers.new_configuration_setting_path(setting: @setting)
      end
    end

    def configured?
      @configuration.setting_data(@setting).present?
    end

    def incomplete?
      @configuration.setting_incomplete?(@setting)
    end
  end
end
