# Data-driven round-trip tests: for each fixture scenario under
# spec/fixtures/import_scenarios/<name>/ that has a helios/config.yaml, verify
# that
#
#   <compose>.bak + .env.bak     →  Import  →  helios/config.yaml
#   helios/config.yaml           →  Export  →  compose.yaml + .env
#
# helios/config.yaml mirrors the production layout where HELIOS stores its
# config under <host_data_path>/helios/ — letting fixtures double as droppable
# stacks for `docker compose up -d`.
#
# Synthetic scenarios live directly under import_scenarios/. Anonymized
# real-world snapshots from actual users live under import_scenarios/real_world/
# and appear in the spec output as "real_world/<name>".
#
# The source compose file may be any of compose.yaml, docker-compose.yaml, or
# docker-compose.yml (with the .bak suffix), matching what HELIOS accepts at
# import time.
#
# Regenerate the expected fixtures with `RAILS_ENV=test bin/rake fixtures:regenerate`.
def scenarios_root
  Rails.root.join('spec/fixtures/import_scenarios')
end

RSpec.describe 'Scenario round-trip' do
  Pathname.glob(scenarios_root.join('**/helios/config.yaml'))
          .map { |p| p.dirname.parent.relative_path_from(scenarios_root).to_s }
          .sort
          .each do |name|
    context "with scenario '#{name}'" do
      let(:scenario_path) { scenarios_root.join(name) }
      let(:compose_backup_path) do
        Compose::FILENAMES.lazy.map { |f| scenario_path.join("#{f}.bak") }.find(&:file?)
      end
      let(:stack_reader) do
        Import::StackReader.new(
          compose_path: compose_backup_path,
          env_path: scenario_path.join('.env.bak'),
        )
      end

      before { with_config_yaml }

      it 'round-trips backup → config → compose/env', :aggregate_failures do
        config = Import::ConfigurationImporter.new(stack_reader).import!

        # Export materializes auto-generated defaults (admin_password,
        # secret_key_base, …) into Configuration.path. Compare config.yaml
        # after the export so the snapshot includes those values, matching
        # the post-defaults state that real HELIOS instances persist.
        Export::Builder.new(config).write!

        imported = YAML.safe_load_file(Configuration.path, permitted_classes: [Date])
        expected = YAML.safe_load_file(scenario_path.join('helios/config.yaml'), permitted_classes: [Date])
        expect(imported).to eq(expected)

        expect(File.read(Compose.path)).to eq(File.read(scenario_path.join('compose.yaml')))
        expect(File.read(Env.path)).to eq(File.read(scenario_path.join('.env')))
      end
    end
  end
end
