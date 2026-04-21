# Data-driven round-trip tests: for each fixture scenario under
# spec/fixtures/import_scenarios/<name>/ that has an expected_config.yaml,
# verify that
#
#   old_compose.yaml + old.env  →  Import  →  expected_config.yaml
#   expected_config.yaml        →  Export  →  expected_compose.yaml + expected.env
#
# Regenerate the expected fixtures with `RAILS_ENV=test bin/rake fixtures:regenerate`.
RSpec.describe 'Scenario round-trip' do
  Pathname.glob(Rails.root.join('spec/fixtures/import_scenarios/*/expected_config.yaml'))
          .map { |p| p.dirname.basename.to_s }
          .sort
          .each do |name|
    context "with scenario '#{name}'" do
      let(:scenario_path) { Rails.root.join('spec/fixtures/import_scenarios', name) }
      let(:stack_reader) do
        Import::StackReader.new(
          compose_path: scenario_path.join('old_compose.yaml'),
          env_path: scenario_path.join('old.env'),
        )
      end

      before { with_config_yaml }

      it 'imports old_compose.yaml + old.env into the expected config' do
        Import::ConfigurationImporter.new(stack_reader).import!

        imported = YAML.safe_load_file(Configuration.path, permitted_classes: [Date])
        expected = YAML.safe_load_file(scenario_path.join('expected_config.yaml'), permitted_classes: [Date])

        expect(imported).to eq(expected)
      end

      it 'exports config into the expected compose.yaml and .env' do
        config = Import::ConfigurationImporter.new(stack_reader).import!
        Export::Builder.new(config).write!

        expect(File.read(Compose.path)).to eq(File.read(scenario_path.join('expected_compose.yaml')))
        expect(File.read(Env.path)).to eq(File.read(scenario_path.join('expected.env')))
      end
    end
  end
end
