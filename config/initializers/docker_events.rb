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

  DockerHost::EventsListener.start
end

# Graceful shutdown when server stops
at_exit do
  if DockerHost::EventsListener.running?
    DockerHost::EventsListener::Logging.logger.info('Server shutting down...')
    DockerHost::EventsListener.stop
  end
end

# In development: restart listener after code reload to pick up changes
if Rails.env.development?
  Rails.application.config.to_prepare do
    # This runs after code is reloaded
    # The listener instance survives reload (stored in Rails.config),
    # but we restart it to pick up any code changes
    if DockerHost::EventsListener.running?
      DockerHost::EventsListener::Logging.logger.info(
        'Code reloaded, restarting...',
      )
      DockerHost::EventsListener.restart
    end
  end
end
