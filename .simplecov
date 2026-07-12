# SimpleCov configuration (config only — do NOT call `SimpleCov.start` here;
# 1.0 deprecates starting from `.simplecov`). Coverage tracking starts
# explicitly via `SimpleCov.start 'rails'` in spec/spec_helper.rb, and the
# parallel results are collated in bin/coverage. SimpleCov auto-loads this
# file on every `require 'simplecov'`, so both paths share one config.

SimpleCov.configure do
  # turbo_tests runs each parallel slice as its own process; a slow slice can
  # finish well after the first, past the 600s default window that would
  # otherwise drop its resultset from the merged report.
  merge_timeout 3600

  # Extra report groups on top of the ones the 'rails' profile already adds
  # (Controllers, Models, Jobs, …). HELIOS is service- and ViewComponent-heavy.
  group 'Services', 'app/services'
  group 'Components', 'app/components'

  # Framework boilerplate with no meaningful logic to cover.
  skip 'app/jobs/application_job.rb'
  skip 'app/models/application_record.rb'
  skip 'app/channels/application_cable/connection.rb'
  skip 'app/channels/application_cable/channel.rb'
end
