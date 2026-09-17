module SettingLink
  # Chip-style entry for the Settings page: icon + label, and nothing else.
  # Used for every setting in every group; SettingSection (the full card) is
  # reserved for the Datasources page where status and counts carry more
  # meaning per item.
  #
  # No chip reports a state. Every setting on this page either ships with a
  # workable value or is asked for before the page is reachable at all (see
  # CommissioningController), so there is no state left to report.
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
  end
end
