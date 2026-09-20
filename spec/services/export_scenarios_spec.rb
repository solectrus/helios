# Data-driven export tests: for each scenario under
# spec/fixtures/export_scenarios/<name>/, verify that
#
#   helios/config.yaml.bak  →  Migrate  →  helios/config.yaml
#   helios/config.yaml      →  Export   →  compose.yaml + .env
#
# Where import_scenarios/ starts at a foreign stack and runs the importer,
# these start at a config.yaml taken from a running HELIOS instance, usually
# on an older schema. That covers two things the import scenarios cannot:
# the ConfigurationMigrations chain against a real file rather than a
# hand-built hash, and the export against output a released HELIOS version
# actually produced.
#
# Regenerate the expected fixtures with `RAILS_ENV=test bin/rake fixtures:regenerate`.
def export_scenarios_root
  Rails.root.join('spec/fixtures/export_scenarios')
end

RSpec.describe 'Scenario export' do
  Pathname.glob(export_scenarios_root.join('*/helios/config.yaml.bak'))
          .map { |p| p.dirname.parent.relative_path_from(export_scenarios_root).to_s }
          .sort
          .each do |name|
    context "with scenario '#{name}'" do
      let(:scenario_path) { export_scenarios_root.join(name) }

      before do
        with_config_yaml
        FileUtils.mkdir_p(File.dirname(Configuration.path))
        FileUtils.cp(scenario_path.join('helios/config.yaml.bak'), Configuration.path)
      end

      it 'migrates and exports the stack', :aggregate_failures do
        ConfigurationMigrator.run!
        Current.configuration = nil
        Export::Builder.new(Configuration.current).write!

        migrated = YAML.safe_load_file(Configuration.path, permitted_classes: [Date])
        expected = YAML.safe_load_file(scenario_path.join('helios/config.yaml'), permitted_classes: [Date])
        expect(migrated).to eq(expected)

        expect(File.read(Compose.path)).to eq(File.read(scenario_path.join('compose.yaml')))
        expect(File.read(Env.path)).to eq(File.read(scenario_path.join('.env')))
      end
    end
  end
end
