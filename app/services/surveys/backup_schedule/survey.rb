module Surveys
  module BackupSchedule
    class Survey < Base
      private

      # Inject the actually-configured timezone into the schedule_time hint, so
      # the user reads e.g. "Applies in the Europe/Berlin timezone." instead of
      # a vague "server timezone". This is the zone the scheduler fires in — the
      # helios container gets it via the TZ env var (see Export::Services::Helios).
      def customize!(data)
        element = find_element(data, 'schedule_time')
        return unless element

        element['description'] = self.class.localized(
          en: "Applies in the \"#{timezone}\" timezone. Only the five most recent " \
              'backups are kept; older ones are removed automatically.',
          de: "Gilt in der Zeitzone \"#{timezone}\". Es werden weiterhin nur die " \
              'fünf neuesten Sicherungen aufbewahrt, ältere automatisch entfernt.',
        )
      end

      def timezone
        Configuration.current.system.timezone.presence || 'Europe/Berlin'
      end
    end
  end
end
