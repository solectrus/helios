RSpec.describe Export::Env::Unmanaged do
  subject(:env) { Export::Env.new(Configuration.current).to_s }

  # Orphan .env lines are rendered last and `env[]=` updates in place, so an
  # orphan sharing a key with a managed section would silently overwrite the
  # value HELIOS just derived from the configuration. TIBBER_TOKEN is the real
  # case: it was captured as an orphan before HELIOS managed the collector.
  context 'when an orphan variable collides with a managed one' do
    before do
      with_config_yaml(
        'tibber' => { 'token' => 'from-the-survey' },
        '_unmanaged' => { 'env_vars' => { 'TIBBER_TOKEN' => 'stale-orphan', 'DOZZLE_LEVEL' => 'debug' } },
      )
    end

    it 'keeps the managed value' do
      expect(env).to include('TIBBER_TOKEN=from-the-survey')
      expect(env).not_to include('stale-orphan')
    end

    it 'still preserves unrelated orphans' do
      expect(env).to include('DOZZLE_LEVEL=debug')
    end
  end

  # An unmanaged MQTT-style collector carries one block of MAPPING_<N>_* keys
  # per sensor. Grouping by the plain prefix would merge them all into one
  # "MAPPING" block, so the index is part of the group title.
  context 'with an unmanaged service carrying indexed mapping variables' do
    before do
      with_config_yaml(
        '_unmanaged' => {
          'services' => {
            'legacy-collector' => {
              'image' => 'example/legacy:latest',
              'env_values' => {
                'MAPPING_0_TOPIC' => 'a/b',
                'MAPPING_1_TOPIC' => 'c/d',
                'LEGACY_INTERVAL' => '30',
              },
            },
          },
        },
      )
    end

    it 'separates the mappings by index and keeps the rest under its prefix' do
      expect(env).to include('--- Mapping 0', '--- Mapping 1', '--- LEGACY')
    end
  end

  context 'when every orphan is shadowed by a managed section' do
    before do
      with_config_yaml(
        'tibber' => { 'token' => 'from-the-survey' },
        '_unmanaged' => { 'env_vars' => { 'TIBBER_TOKEN' => 'stale-orphan' } },
      )
    end

    it 'omits the section header rather than leaving an empty one behind' do
      expect(env).not_to include('Unmanaged variables (preserved from existing installation)')
    end
  end
end
