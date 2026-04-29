# Schema migrations for config.yaml. Each migration transforms the raw hash
# loaded from disk; persistence and version bookkeeping live in
# ConfigurationMigrator.
#
# Migration files live in app/services/configuration_migrations/ and are named
# `NNN_<descriptive>.rb` (e.g. `001_create_dashboard_section.rb`). They define
# a class under this module that inherits from Base and uses the DSL there
# (`version`, plus operation helpers like `move`). Order is derived from
# `version`, not from the filename — but the numeric prefix keeps the
# directory listing chronological. Class names express the activity, matching
# ActiveRecord conventions (e.g. `CreateDashboardSection`).
#
# Because the numeric prefix breaks Zeitwerk's filename-to-constant mapping,
# the directory is removed from autoload (see config/application.rb) and the
# files are required explicitly here.
module ConfigurationMigrations
  MIGRATION_DIR = File.expand_path('configuration_migrations', __dir__).freeze

  require File.join(MIGRATION_DIR, 'base')
  Dir.glob(File.join(MIGRATION_DIR, '[0-9]*.rb')).each { |path| require path }

  REGISTRY = constants
             .map { |c| const_get(c) }
             .grep(Class)
             .select { |c| c.respond_to?(:version) && c.version }
             .sort_by(&:version)
             .freeze

  def self.current_version
    REGISTRY.last&.version || 0
  end

  def self.pending(current_version)
    REGISTRY.select { |m| m.version > current_version }
  end
end
