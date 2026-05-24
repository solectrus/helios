# Background uploader for the S3 backup destination. The detached
# BackupRunner container writes the finished tar into the local staging
# dir and exits; this class then waits for the container to drain,
# uploads the tar through aws-sdk-s3, records the DB row, and removes
# the local copy.
#
# Lives in the HELIOS Rails process, not in a detached container. A
# HELIOS restart (e.g. a Watchtower self-update) therefore kills the
# upload mid-flight — the tar stays in staging so the next
# `BackupRepository.detect_completion!` call can re-spawn the uploader
# via `start_async`. Multipart uploads aborted that way are cleaned up
# by aws-sdk-s3 before the next attempt starts.
#
# Only one upload runs at a time across the whole process (the class
# mutex enforces it). The detached BackupRunner enforces the same
# single-flight invariant on its side via a fixed container name.
class BackupRepository
  module S3
    class Uploader
      POLL_INTERVAL = 2.seconds
      CONTAINER_WAIT_TIMEOUT = 2.hours

      class << self
        # Starts an upload thread for the given staged tar. No-op if a
        # thread is already running. Returns true if a new thread was
        # spawned.
        def start_async(filename)
          mutex.synchronize do
            return false if @thread&.alive?

            @started_at = Time.current
            @filename = filename
            # A bare Thread.new is intentional here — this work is
            # explicitly process-local (single uploader, killed by HELIOS
            # restart, picked back up via the resume path).
            @thread = Thread.new(filename) do |f| # rubocop:disable ThreadSafety/NewThread
              Rails.application.executor.wrap { run(f) }
            end
            true
          end
        end

        # Snapshot of the live upload, or nil if no thread is running.
        # Shape matches BackupRepository::InProgress so BackupRunner can
        # surface it through its existing in_progress API. `progress`
        # reflects the most recent TransferManager callback (0.0..1.0).
        def current
          mutex.synchronize do
            return nil unless @thread&.alive?

            BackupRepository::InProgress.new(
              started_at: @started_at, filename: @filename,
              phase: :uploading, progress: @progress || 0.0
            )
          end
        end

        def running?
          mutex.synchronize { @thread&.alive? || false }
        end

        private

        # The class instance variables here (@mutex, @thread, @started_at,
        # @filename) are the singleton state of the upload coordinator —
        # there is only ever one uploader per HELIOS process. Rubocop's
        # ThreadSafety/ClassInstanceVariable cop is silenced because the
        # state is guarded by @mutex.
        # rubocop:disable ThreadSafety/ClassInstanceVariable
        def mutex
          @mutex ||= Mutex.new
        end
        # rubocop:enable ThreadSafety/ClassInstanceVariable

        def run(filename) # rubocop:disable Metrics/MethodLength,Metrics/AbcSize
          wait_for_container_exit
          return if error_file_present?
          return unless tar_present?(filename)

          BackupRepository::S3.upload_from_staging!(filename, progress_callback: progress_recorder)
          BackupRepository::S3.record_from_staging!(filename)
          FileUtils.rm_f(staging_path(filename))
        rescue BackupRepository::Error => e
          handle_failure(filename, e.message)
        rescue StandardError => e
          Rails.logger.error("BackupRepository::S3::Uploader #{e.class}: #{e.message}")
          handle_failure(filename, "#{e.class}: #{e.message}")
        ensure
          mutex.synchronize do
            @thread = nil
            @started_at = nil
            @filename = nil
            @progress = nil
          end
        end

        # Callback the TransferManager invokes after each part with
        # (bytes_uploaded, bytes_total). The mutex guards the cross-thread
        # write so #current sees a consistent snapshot.
        def progress_recorder
          lambda do |uploaded, total|
            ratio = total.positive? ? uploaded.to_f / total : 0.0
            mutex.synchronize { @progress = ratio.clamp(0.0, 1.0) }
          end
        end

        def handle_failure(filename, message)
          write_error_locally("S3 upload failed: #{message}")
          FileUtils.rm_f(staging_path(filename))
        end

        # Polls `docker inspect` until the BackupRunner container is no
        # longer running. A misbehaving container is bounded by
        # CONTAINER_WAIT_TIMEOUT so the thread eventually unblocks and
        # can be cleaned up.
        def wait_for_container_exit
          deadline = Time.current + CONTAINER_WAIT_TIMEOUT
          while BackupRunner.running?
            raise "BackupRunner container did not exit within #{CONTAINER_WAIT_TIMEOUT}" if Time.current > deadline

            sleep POLL_INTERVAL.to_f
          end
        end

        def error_file_present?
          ::File.exist?(error_path)
        end

        def tar_present?(filename)
          ::File.exist?(staging_path(filename))
        end

        def staging_path(filename)
          ::File.join(BackupRepository::S3.directory, filename)
        end

        def error_path
          ::File.join(BackupRepository::S3.directory, BackupRepository::ERROR_FILENAME)
        end

        def write_error_locally(message)
          FileUtils.mkdir_p(BackupRepository::S3.directory)
          ::File.write(error_path, message)
        end
      end
    end
  end
end
