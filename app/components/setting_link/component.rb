module SettingLink
  # Chip-style entry for the Settings page: icon + label. Used for every
  # setting in every group; SettingSection (the full card) is reserved for the
  # Datasources page where status and counts carry more meaning per item.
  #
  # A chip in the required tier carries its state as well, a check once the
  # setting holds a value and a warning while it does not. Optional chips stay
  # plain: they ship with a workable value and have no state worth reporting.
  class Component < ViewComponent::Base
    def initialize(setting:, configuration:, required: false)
      super()
      @setting = setting
      @configuration = configuration
      @required = required
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

    def required?
      @required
    end

    def incomplete?
      @configuration.setting_incomplete?(@setting)
    end

    def state_icon
      incomplete? ? 'fa-triangle-exclamation text-warning' : 'fa-check text-success'
    end

    def state_label
      incomplete? ? t('.incomplete') : t('.complete')
    end
  end
end
