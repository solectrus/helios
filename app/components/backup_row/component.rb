module BackupRow
  class Component < ViewComponent::Base
    # `restore_in_progress` is a BackupRepository::InProgress when *this*
    # specific backup is the one being restored right now, or nil
    # otherwise. The helper turns it into a localized label that includes
    # the live S3 download percentage during the :downloading phase.
    # `actions_disabled_reason` is nil when actions are available, or a
    # short localized string explaining why they aren't (e.g. "A CSV import
    # is currently running."). When present, the dropdown trigger itself is
    # disabled and the reason is shown as a hover tooltip.
    def initialize(backup:, restore_in_progress:, actions_disabled_reason:)
      super()
      @backup = backup
      @restore_in_progress = restore_in_progress
      @actions_disabled_reason = actions_disabled_reason
    end

    private

    attr_reader :backup, :actions_disabled_reason

    def restore_current?
      @restore_in_progress.present?
    end

    def restore_label
      helpers.restore_in_progress_label(@restore_in_progress) if restore_current?
    end

    def actions_disabled?
      actions_disabled_reason.present?
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
