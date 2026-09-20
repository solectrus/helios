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
# files are loaded explicitly here.
module ConfigurationMigrations
  MIGRATION_DIR = File.expand_path('configuration_migrations', __dir__).freeze

  # `load`, not `require`: this file is managed by Zeitwerk, so a reload in
  # development drops the ConfigurationMigrations namespace and every constant
  # under it, Base included. A second `require` of a file Ruby already read
  # does nothing, and the body would leave the namespace half built. `load`
  # reads the files again.
  load File.join(MIGRATION_DIR, 'base.rb')
  Dir.glob(File.join(MIGRATION_DIR, '[0-9]*.rb')).each { |path| load path }

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
