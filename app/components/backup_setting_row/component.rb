module BackupSettingRow
  # One row in the backup-settings bar on the Backups page: an icon tile, an
  # uppercase label with its current value below, and a chevron. Used for both
  # the destination and the automatic-schedule entries, which share the same
  # markup and only differ in icon, label and value.
  class Component < ViewComponent::Base
    def initialize(path:, icon:, label:, value:, icon_class: 'bg-base-content/5 text-base-content/70')
      super()
      @path = path
      @icon = icon
      @label = label
      @value = value
      @icon_class = icon_class
    end
  end
end
