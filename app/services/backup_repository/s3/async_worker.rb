class BackupRepository
  module S3
    # Base for process-local single-flight transfer workers (Uploader,
    # Downloader). Owns the mutex/thread/state machinery and the
    # InProgress snapshot; subclasses implement `phase` and `run`.
    #
    # Each worker is intentionally killed by a HELIOS restart — the
    # uploader's resume path re-spawns it via BackupRunner.in_progress;
    # the downloader simply asks the user to retry.
    class AsyncWorker
      class << self
        # Starts the worker thread. No-op if one is already alive.
        # Returns true if a new thread was spawned. Extra kwargs are
        # forwarded to the subclass's `run` (e.g. Downloader uses
        # `total:` to size the progress callback).
        def start_async(filename, **, &on_complete) # rubocop:disable Naming/BlockForwarding
          mutex.synchronize do
            return false if @thread&.alive?

            @started_at = Time.current
            @filename = filename
            @progress = nil
            # Bare Thread.new is intentional: process-local single-flight
            # work, see class docstring. `on_complete` is captured as a
            # named block because anonymous `&` does not survive the
            # Thread.new-block boundary. The trailing broadcast tells the
            # status bar (and /backups) the worker is done — without it
            # the UI would keep showing "in progress" until the user
            # navigates back to /backups.
            @thread = Thread.new(filename) do |f| # rubocop:disable ThreadSafety/NewThread
              # rubocop:disable Naming/BlockForwarding
              Rails.application.executor.wrap { run(f, **, &on_complete) }
              # rubocop:enable Naming/BlockForwarding
            ensure
              Orchestration::HeliosOperationBroadcaster.broadcast!
            end
            true
          end
        end

        # Snapshot of the live transfer, or nil if no thread is running.
        # Shape matches BackupRepository::InProgress.
        def current
          mutex.synchronize do
            return nil unless @thread&.alive?

            BackupRepository::InProgress.new(
              started_at: @started_at, filename: @filename,
              phase: phase, progress: @progress || 0.0
            )
          end
        end

        def running?
          mutex.synchronize { @thread&.alive? || false }
        end

        # Subclass hook — returned as InProgress#phase.
        def phase
          raise NotImplementedError
        end

        private

        # State guarded by @mutex; the ThreadSafety cop is silenced for
        # this single-flight singleton state.
        # rubocop:disable ThreadSafety/ClassInstanceVariable
        def mutex
          @mutex ||= Mutex.new
        end
        # rubocop:enable ThreadSafety/ClassInstanceVariable

        # Captures the latest transfer-manager callback in #current.
        # Skips the cross-thread write when the rounded percent has not
        # changed since the last call — aws-sdk-s3 fires the callback
        # after each part / each 64 KB chunk (thousands of times per
        # large transfer), but the UI only shows integer percent.
        def progress_recorder
          lambda do |done, total|
            ratio = total.to_i.positive? ? done.to_f / total : 0.0
            rounded = (ratio.clamp(0.0, 1.0) * 100).round / 100.0
            mutex.synchronize { @progress = rounded unless @progress == rounded }
          end
        end

        def reset_state!
          mutex.synchronize do
            @thread = nil
            @started_at = nil
            @filename = nil
            @progress = nil
          end
        end
      end
    end
  end
end
