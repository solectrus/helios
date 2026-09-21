# A config.yaml an older HELIOS wrote:
#
#   input/config.yaml  →  Migrate  →  snapshot/helios/config.yaml
#   snapshot/helios/config.yaml  →  Export  →  snapshot/{compose.yaml,.env}
#
# Two things the import family cannot cover. The ConfigurationMigrations chain
# runs against a real file, where every config.yaml an importer produces
# already carries the current schema version. And the export runs against a
# configuration that a released version already turned into a stack, so a
# donor who also sent that stack lets you see every change the export made
# since their release.
RSpec.describe 'Export scenario' do
  ScenarioSnapshot.names('export').each do |name|
    context "with '#{name}'" do
      let(:scenario_path) { ScenarioSnapshot.path('export', name) }
      let(:snapshot_path) { scenario_path.join('snapshot') }

      before do
        with_config_yaml
        FileUtils.mkdir_p(File.dirname(Configuration.path))
        FileUtils.cp(scenario_path.join('input/config.yaml'), Configuration.path)
      end

      it 'migrates the configuration and exports the stack' do
        ConfigurationMigrator.run!
        Current.configuration = nil
        Export::Builder.new(Configuration.current).write!

        verify_snapshot!(snapshot_path)
      end
    end
  end
end
