# Background uploader for the S3 backup destination. The detached
# BackupRunner container writes the finished tar into the local staging
# dir and exits; this class then waits for the container to drain,
# uploads the tar through aws-sdk-s3, records the DB row, and removes
# the local copy.
#
# A HELIOS restart mid-upload (e.g. Watchtower self-update) kills the
# thread — the tar stays in staging and BackupRunner.in_progress
# re-spawns the uploader via `start_async`. Multipart uploads aborted
# that way are cleaned up by aws-sdk-s3 before the next attempt starts.
class BackupRepository
  module S3
    class Uploader < AsyncWorker
      POLL_INTERVAL = 2.seconds
      CONTAINER_WAIT_TIMEOUT = 2.hours

      class << self
        def default_phase = :uploading

        private

        def run(filename)
          wait_for_container_exit
          return if error_file_present?

          upload_and_prune!(filename)
        rescue BackupRepository::Error => e
          handle_failure(filename, e.message)
        rescue StandardError => e
          logger.error("#{e.class}: #{e.message}")
          handle_failure(filename, "#{e.class}: #{e.message}")
        ensure
          reset_state!
        end

        def upload_and_prune!(filename)
          staging = BackupRepository::S3.staging_path(filename)
          return unless ::File.exist?(staging)

          BackupRepository::S3.upload_from_staging!(filename, progress_callback: progress_recorder)
          BackupRepository::S3.record_from_staging!(filename)
          FileUtils.rm_f(staging)
          advance_phase(:pruning)
          BackupRepository.prune!
        end

        def handle_failure(filename, message)
          BackupRepository::S3.write_error_file!(
            BackupRepository::ERROR_FILENAME, "S3 upload failed: #{message}"
          )
          FileUtils.rm_f(BackupRepository::S3.staging_path(filename))
        end

        # Polls `docker inspect` until the BackupRunner container is no
        # longer running. CONTAINER_WAIT_TIMEOUT bounds a misbehaving
        # container so the thread eventually unblocks.
        def wait_for_container_exit
          deadline = Time.current + CONTAINER_WAIT_TIMEOUT
          while BackupRunner.running?
            raise "BackupRunner container did not exit within #{CONTAINER_WAIT_TIMEOUT}" if Time.current > deadline

            sleep POLL_INTERVAL.to_f
          end
        end

        def error_file_present?
          ::File.exist?(::File.join(BackupRepository::S3.directory, BackupRepository::ERROR_FILENAME))
        end
      end
    end
  end
end
