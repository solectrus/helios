RSpec.describe ConfigurationMigrations::SplitInfluxdbTokens do
  subject(:up) { described_class.new.up(data) }

  context 'with a legacy single-token influxdb section' do
    let(:data) do
      { 'influxdb' => { 'token' => 'legacy-secret', 'org' => 'solectrus' } }
    end

    it 'splits the token into the four role-specific fields' do
      up
      expect(data['influxdb']).to eq(
        'org' => 'solectrus',
        'token_admin' => 'legacy-secret',
        'token_readwrite' => 'legacy-secret',
        'token_write' => 'legacy-secret',
        'token_read' => 'legacy-secret',
      )
    end
  end

  context 'when the influxdb section is missing' do
    let(:data) { { 'system' => { 'timezone' => 'Europe/Berlin' } } }

    it 'leaves the data untouched' do
      expect(up).to eq('system' => { 'timezone' => 'Europe/Berlin' })
    end
  end

  context 'when token is blank' do
    let(:data) { { 'influxdb' => { 'token' => '', 'org' => 'solectrus' } } }

    it 'drops the empty token without populating the role fields' do
      up
      expect(data['influxdb']).to eq('org' => 'solectrus')
    end
  end

  context 'when role fields already exist' do
    let(:data) do
      {
        'influxdb' => {
          'token' => 'legacy',
          'token_admin' => 'kept-admin',
          'token_write' => 'kept-write',
        },
      }
    end

    it 'fills only the missing role fields and removes the legacy key' do
      up
      expect(data['influxdb']).to eq(
        'token_admin' => 'kept-admin',
        'token_readwrite' => 'legacy',
        'token_write' => 'kept-write',
        'token_read' => 'legacy',
      )
    end
  end

  it 'is registered as version 3' do
    expect(described_class.version).to eq(3)
  end
end
