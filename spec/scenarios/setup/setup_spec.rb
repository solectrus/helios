# A new installation, answered screen by screen:
#
#   answers.yml  →  Walk the surveys  →  payload
#   payload      →  Save              →  snapshot/helios/config.yaml
#   snapshot/helios/config.yaml  →  Export  →  snapshot/{compose.yaml,.env}
#
# The only family that starts at no stack at all, so the only one that covers
# what a user actually does. The walk runs the real survey-core Model over the
# survey HELIOS serves (see SetupScenario), which makes a renamed question, a
# new mandatory one or a changed visibleIf break the scenario instead of
# passing silently.
#
# The stack does not start. `docker compose config` is the last word on the
# output, and says whether Docker accepts the pair of files.
RSpec.describe 'Setup scenario' do
  ScenarioSnapshot.names('setup').each do |name|
    context "with '#{name}'" do
      let(:scenario_path) { ScenarioSnapshot.path('setup', name) }
      let(:snapshot_path) { scenario_path.join('snapshot') }
      let(:compose_path) { snapshot_path.join('compose.yaml').to_s }
      let(:env_path) { snapshot_path.join('.env').to_s }

      before { with_config_yaml }

      it 'answers the surveys and exports the stack' do
        config = SetupScenario.new(scenario_path).replay!
        Export::Builder.new(config).write!

        verify_snapshot!(snapshot_path)
      end

      it_behaves_like 'valid Docker Compose configuration'
    end
  end
end
