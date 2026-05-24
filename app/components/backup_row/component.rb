module BackupRow
  class Component < ViewComponent::Base
    # `restore_in_progress` is a BackupRepository::InProgress when *this*
    # specific backup is the one being restored right now, or nil
    # otherwise. The helper turns it into a localized label that includes
    # the live S3 download percentage during the :downloading phase.
    def initialize(backup:, restore_in_progress:, actions_disabled:)
      super()
      @backup = backup
      @restore_in_progress = restore_in_progress
      @actions_disabled = actions_disabled
    end

    private

    attr_reader :backup

    def restore_current?
      @restore_in_progress.present?
    end

    def restore_label
      helpers.restore_in_progress_label(@restore_in_progress) if restore_current?
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
