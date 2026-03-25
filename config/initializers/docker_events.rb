# Manage Docker events listener lifecycle
#
# The listener enables real-time container status updates via Turbo Streams.
# It runs in a background thread and survives code reloading in development.
# Started/stopped automatically when browsers connect/disconnect via ActionCable.
# Logs are written to log/docker_events.log

Rails.application.config.after_initialize do
  Orchestration::EventsListener.initialize_lifecycle
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
# Only restart if already running — subscribers trigger the initial start.
if Rails.env.development?
  Rails.application.config.to_prepare do
    Orchestration::EventsListener.restart if Orchestration::EventsListener.running?
  end
end
