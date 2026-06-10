require 'active_support/core_ext/integer/time'

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = {
    'cache-control' => "public, max-age=#{1.year.to_i}",
  }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Behind a HELIOS-managed Traefik the UI is served over HTTPS with TLS
  # terminated by the proxy; the exported compose.yaml then sets FORCE_SSL=true
  # (see Export::Services::Helios). Turns on secure cookies, HSTS and the
  # http→https redirect. Direct host-port deployments are plain HTTP and leave
  # the variable unset.
  if ActiveModel::Type::Boolean.new.cast(ENV.fetch('FORCE_SSL', false))
    config.assume_ssl = true
    config.force_ssl = true
  end

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [:request_id]
  config.logger = ActiveSupport::TaggedLogging.logger($stdout)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch('RAILS_LOG_LEVEL', 'info')

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = '/up'

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Use a thread-safe in-process cache. HELIOS runs as a single Puma process
  # with the in-process :async job adapter, so every cache user is process-local
  # anyway. The Rails default (:file_store) has a directory race between
  # concurrent writes and Container.invalidate_cache's empty-directory pruning,
  # which surfaces as Errno::ENOENT on the heavily parallel /services page.
  config.cache_store = :memory_store

  # Run Active Jobs in an in-process thread pool. Jobs are only ever enqueued
  # by user clicks, and Docker state is authoritative — EventsListener will
  # reconcile UI state from Docker events if a job is lost on restart.
  config.active_job.queue_adapter = :async

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Enable DNS rebinding protection and other `Host` header attacks.
  # config.hosts = [
  #   "example.com",     # Allow requests from example.com
  #   /.*\.example\.com/ # Allow requests from subdomains like `www.example.com`
  # ]
  #
  # Skip DNS rebinding protection for the default health check endpoint.
  # config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
