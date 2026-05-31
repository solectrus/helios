require_relative 'boot'

require 'rails'
# Pick the frameworks you want:
require 'active_model/railtie'
require 'active_job/railtie'
require 'active_record/railtie'
# require "active_storage/engine"
require 'action_controller/railtie'
# require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require 'action_view/railtie'
require 'action_cable/engine'
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

require_relative '../lib/startup_check_middleware'

module Helios
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Migration files in app/services/configuration_migrations/ use a numeric
    # filename prefix (`001_*.rb`) for chronological ordering. That prefix
    # breaks Zeitwerk's filename-to-constant mapping, so the directory is
    # excluded from autoload and required explicitly by ConfigurationMigrations.
    Rails.autoloaders.main.ignore(Rails.root.join('app/services/configuration_migrations'))

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # The app timezone follows the container's TZ env var (set by HELIOS for
    # the helios service). This makes Time.zone / Time.current correct in every
    # thread — web requests and background workers (scheduler, S3 uploader) —
    # without per-thread zone juggling.
    config.time_zone = ENV.fetch('TZ', 'Europe/Berlin')
    # config.eager_load_paths << Rails.root.join("extras")

    # Don't generate system test files.
    config.generators.system_tests = nil

    # Path where stack files (compose.yaml, .env) are stored.
    # Defaults to /data in production; overridden in development/test.
    config.data_path = '/data'

    # Block requests with a fail screen when startup prerequisites are not met.
    # Only active in production — development/test rely on local file paths.
    if ENV['RAILS_ENV'] == 'production'
      config.middleware.insert(0, StartupCheckMiddleware)
    end

    config.x.git.commit_version =
      ENV.fetch('COMMIT_VERSION') { `git describe --always --abbrev=7`.chomp }

    config.x.git.commit_time =
      ENV.fetch('COMMIT_TIME') { `git show -s --format=%cI`.chomp }

    config.x.git.commit_branch =
      ENV.fetch('COMMIT_BRANCH') { `git rev-parse --abbrev-ref HEAD`.chomp }
  end
end
