# Background downloader for the S3 backup destination. The
# RestoreRunner needs the tar on disk before its detached docker:cli
# container can read it; this class fetches the tar through
# aws-sdk-s3, then calls the supplied block (which launches the
# RestoreRunner container).
#
# A HELIOS restart during the download leaves a partial tar in staging
# and no live thread — the user simply restarts the restore; we do not
# try to resume mid-download. (The download is the cheapest part of
# the restore.)
class BackupRepository
  module S3
    class Downloader < AsyncWorker
      class << self
        def default_phase = :downloading

        private

        def run(filename, total: nil)
          return unless perform_download(filename, total)
          return unless block_given?

          begin
            yield
          rescue StandardError => e
            Rails.logger.error("BackupRepository::S3::Downloader after-download #{e.class}: #{e.message}")
            BackupRepository::S3.write_error_file!(RestoreRunner::ERROR_FILENAME, e.message)
          end
        ensure
          reset_state!
        end

        # Returns true if the tar is now in staging, false otherwise —
        # callers skip the on_complete step in the false case (no point
        # starting the restore container without a tar).
        def perform_download(filename, total)
          BackupRepository::S3.download_to_staging!(
            filename, progress_callback: progress_recorder, total: total
          )
          true
        rescue BackupRepository::Error => e
          handle_download_failure(filename, e.message)
          false
        rescue StandardError => e
          Rails.logger.error("BackupRepository::S3::Downloader download #{e.class}: #{e.message}")
          handle_download_failure(filename, "#{e.class}: #{e.message}")
          false
        end

        def handle_download_failure(filename, message)
          BackupRepository::S3.write_error_file!(
            RestoreRunner::ERROR_FILENAME, "S3 download failed: #{message}"
          )
          FileUtils.rm_f(BackupRepository::S3.staging_path(filename))
        end
      end
    end
  end
end
