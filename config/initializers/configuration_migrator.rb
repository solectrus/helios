# Apply pending schema migrations to config.yaml before any controller or
# service touches Configuration.current. Skipped in the test environment —
# specs run against fixtures and helpers that already match the current
# schema version (see spec/support/configuration_helpers.rb).
Rails.application.config.after_initialize do
  next if Rails.env.test?

  ConfigurationMigrator.run!
rescue StandardError => e
  Rails.logger.error("ConfigurationMigrator failed: #{e.class}: #{e.message}")
  raise
end
