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
