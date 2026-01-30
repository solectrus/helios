# Start Docker events listener when the server boots
# This enables real-time status updates via ActionCable

Rails.application.config.after_initialize do
  # Only start in server context, not during rake tasks or console
  next unless defined?(Rails::Server) || defined?(Puma)
  next if Rails.env.test?

  DockerHost::EventsListener.start
end
