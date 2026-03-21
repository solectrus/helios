# Manage Docker events listener lifecycle
#
# The listener enables real-time container status updates via Turbo Streams.
# It runs in a background thread and survives code reloading in development.
# Logs are written to log/docker_events.log

Rails.application.config.after_initialize do
  # Only start in actual web server process
  # Rails::Server is only defined when running `rails server`
  # Puma check covers direct `puma` command
  next unless defined?(Rails::Server) || $PROGRAM_NAME.include?('puma')
  next if Rails.env.test?

  Orchestration::EventsListener.start
end

# Graceful shutdown when server stops
at_exit do
  if Orchestration::EventsListener.running?
    Orchestration::EventsListener::Logging.logger.info('Server shutting down...')
    Orchestration::EventsListener.stop
  end
end

# In development: restart listener after code reload so background threads
# pick up the new code instead of running stale closures.
# Only restart if already running — the initial start is handled above.
if Rails.env.development?
  Rails.application.config.to_prepare do
    Orchestration::EventsListener.restart if Orchestration::EventsListener.running?
  end
end
