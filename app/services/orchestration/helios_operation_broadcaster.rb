module Orchestration
  # Pushes a status-bar replace and a /backups refresh after a backup or
  # restore makes progress that the UI can't observe on its own — e.g.
  # the detached docker container exiting, or the in-process Uploader /
  # Downloader thread completing its work.
  class HeliosOperationBroadcaster
    extend Loggable

    def self.broadcast!(locale: nil)
      BackupRunner.invalidate_in_progress_cache!
      RestoreRunner.invalidate_in_progress_cache!

      with_locale(locale) do
        StatusBarBroadcaster.new.broadcast
        Turbo::StreamsChannel.broadcast_refresh_to('backups')
      end
    rescue StandardError => e
      logger.error("failed: #{e.class}: #{e.message}")
    end

    def self.with_locale(locale, &)
      return yield unless locale

      I18n.with_locale(locale, &)
    end
  end
end
