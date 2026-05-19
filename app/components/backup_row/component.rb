module BackupRow
  class Component < ViewComponent::Base
    def initialize(backup:, restore_current:, actions_disabled:)
      super()
      @backup = backup
      @restore_current = restore_current
      @actions_disabled = actions_disabled
    end

    private

    attr_reader :backup

    def restore_current?
      @restore_current
    end

    def actions_disabled?
      @actions_disabled
    end

    def influxdb_version
      image_version(backup.influxdb_image)
    end

    def postgresql_version
      image_version(backup.postgresql_image)
    end

    # Short version label for a tooltip, e.g. "influxdb:2.9-alpine" → "2.9".
    # Strips the variant suffix; falls back to the raw tag for non-numeric
    # tags such as "develop".
    def image_version(image)
      return if image.blank?

      tag = image.split(':').last
      tag[/\A[\d.]+/] || tag
    end
  end
end
