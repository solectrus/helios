# Background downloader for the S3 backup destination. The
# RestoreRunner needs the tar on disk before its detached docker:cli
# container can read it; this class fetches the tar through
# aws-sdk-s3, then calls the supplied block (which launches the
# RestoreRunner container).
#
# Lives in the HELIOS Rails process, not in a detached container. A
# HELIOS restart during the download leaves a partial tar in staging
# and no live thread — the user simply restarts the restore; we do not
# try to resume mid-download. (The download is the cheapest part of
# the restore.)
#
# Only one download runs at a time per process (class mutex). The
# detached RestoreRunner enforces its own single-flight invariant via
# a fixed container name.
class BackupRepository
  module S3
    class Downloader
      class << self
        # Starts a download thread for the given S3 tar. When the
        # download completes successfully, the supplied block is
        # invoked on the same thread (typically to kick off the
        # detached RestoreRunner container). No-op if a thread is
        # already running. Returns true if a new thread was spawned.
        # `on_complete` is captured as a named proc on purpose: a bare
        # `&` (anonymous block forwarding) does not survive the
        # Thread.new-block boundary.
        def start_async(filename, &on_complete) # rubocop:disable Naming/BlockForwarding
          mutex.synchronize do
            return false if @thread&.alive?

            @started_at = Time.current
            @filename = filename
            @progress = nil
            @thread = Thread.new(filename) do |f| # rubocop:disable ThreadSafety/NewThread
              # rubocop:disable Naming/BlockForwarding
              Rails.application.executor.wrap { run(f, &on_complete) }
              # rubocop:enable Naming/BlockForwarding
            end
            true
          end
        end

        # Snapshot of the live download, or nil if no thread is running.
        # Shape matches BackupRepository::InProgress so RestoreRunner
        # can surface it through its existing in_progress API.
        def current
          mutex.synchronize do
            return nil unless @thread&.alive?

            BackupRepository::InProgress.new(
              started_at: @started_at, filename: @filename,
              phase: :downloading, progress: @progress || 0.0
            )
          end
        end

        def running?
          mutex.synchronize { @thread&.alive? || false }
        end

        private

        # rubocop:disable ThreadSafety/ClassInstanceVariable
        def mutex
          @mutex ||= Mutex.new
        end
        # rubocop:enable ThreadSafety/ClassInstanceVariable

        def run(filename) # rubocop:disable Metrics/MethodLength
          download_succeeded = perform_download(filename)
          return unless download_succeeded
          return unless block_given?

          begin
            yield
          rescue StandardError => e
            Rails.logger.error("BackupRepository::S3::Downloader after-download #{e.class}: #{e.message}")
            write_restore_error(e.message)
          end
        ensure
          mutex.synchronize do
            @thread = nil
            @started_at = nil
            @filename = nil
            @progress = nil
          end
        end

        # Performs the download and reports any failure as a restore
        # error. Returns true if the tar is now in staging, false
        # otherwise — callers should skip the on_complete step in the
        # false case (no point starting the restore container without a
        # tar).
        def perform_download(filename)
          BackupRepository::S3.download_to_staging_with_progress!(filename, progress_callback: progress_recorder)
          true
        rescue BackupRepository::Error => e
          handle_download_failure(filename, e.message)
          false
        rescue StandardError => e
          Rails.logger.error("BackupRepository::S3::Downloader download #{e.class}: #{e.message}")
          handle_download_failure(filename, "#{e.class}: #{e.message}")
          false
        end

        def progress_recorder
          lambda do |downloaded, total|
            ratio = total.positive? ? downloaded.to_f / total : 0.0
            mutex.synchronize { @progress = ratio.clamp(0.0, 1.0) }
          end
        end

        # Writes the restore-error file so detect_completion! surfaces
        # the failure to the user, and clears the partial tar so the
        # next restore attempt starts clean.
        def handle_download_failure(filename, message)
          write_restore_error("S3 download failed: #{message}")
          FileUtils.rm_f(BackupRepository::S3.staging_path(filename))
        end

        def write_restore_error(message)
          FileUtils.mkdir_p(BackupRepository::S3.directory)
          error_path = ::File.join(BackupRepository::S3.directory, RestoreRunner::ERROR_FILENAME)
          ::File.write(error_path, message)
        end
      end
    end
  end
end
