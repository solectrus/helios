# Regenerate compose.yaml/.env on every boot.
#
# After a HELIOS self-update the new image may produce slightly different
# compose.yaml/.env output. Without this rewrite the change would only
# materialize on the next configuration edit, surprising the user with
# "container restart pending" markers in unrelated places.
#
# The write is idempotent: identical exporter output leaves the deployed
# config hashes unchanged.
Rails.application.config.after_initialize do
  next if Rails.env.test?

  configuration = Configuration.current
  next unless configuration.setup_completed?

  Export::Builder.new(configuration).write!
rescue StandardError => e
  Rails.logger.error("Boot stack refresh failed: #{e.class}: #{e.message}")
end
