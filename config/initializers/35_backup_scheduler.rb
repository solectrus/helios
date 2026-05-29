# Automatic-backup scheduler lifecycle (Issue #106)
#
# The scheduler runs in a background thread inside the Puma process. It is
# started/stopped from config/puma.rb (`after_booted` / `after_stopped`) so it only
# runs inside the real server, never under rake, console or RSpec.
#
# Persistent storage for BackupScheduler state — defined here (outside the
# autoload paths) so it survives code reloading in development.
# Concurrent::Map is thread-safe for all subsequent read/write access.
BACKUP_SCHEDULER_STORAGE = Concurrent::Map.new

Rails.application.config.after_initialize do
  BackupScheduler.initialize_lifecycle
end

# Graceful shutdown when the server stops (belt-and-suspenders next to the
# Puma `after_stopped` hook, e.g. for `bin/rails server` without that hook path).
at_exit { BackupScheduler.stop if BackupScheduler.running? }

# In development: restart the thread after a code reload so it picks up the
# new code instead of running a stale closure. Only when already running.
if Rails.env.development?
  Rails.application.config.to_prepare do
    BackupScheduler.restart if BackupScheduler.running?
  end
end
