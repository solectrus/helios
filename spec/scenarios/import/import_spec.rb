# A foreign stack, adopted:
#
#   input/{compose.yaml,.env}  →  Import  →  snapshot/helios/config.yaml
#   snapshot/helios/config.yaml  →  Export  →  snapshot/{compose.yaml,.env}
#
# The widest of the three families. Its donor stacks come from real users and
# cover configurations nobody would think to write by hand.
#
# The source compose file may carry any name HELIOS accepts at import time
# (see Compose::FILENAMES), and a donor that keeps everything inline in
# compose ships no `.env` at all (real_world/user17).
RSpec.describe 'Import scenario' do
  ScenarioSnapshot.names('import').each do |name|
    context "with '#{name}'" do
      let(:scenario_path) { ScenarioSnapshot.path('import', name) }
      let(:snapshot_path) { scenario_path.join('snapshot') }
      let(:stack_reader) do
        Import::StackReader.new(
          compose_path: Compose::FILENAMES.lazy.map { |f| scenario_path.join('input', f) }.find(&:file?),
          env_path: scenario_path.join('input/.env'),
        )
      end

      before { with_config_yaml }

      it 'adopts the stack and exports it again' do
        config = Import::ConfigurationImporter.new(stack_reader).import!

        # The export materializes the auto-generated defaults (admin_password,
        # secret_key_base, …) into config.yaml, so the snapshot of it is taken
        # in the same state the stack files are.
        Export::Builder.new(config).write!

        verify_snapshot!(snapshot_path)
      end
    end
  end
end
