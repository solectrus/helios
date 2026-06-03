RSpec.describe Surveys::Builder do
  describe '#call' do
    it 'resolves a known setting to its Survey class and renders the JSON' do
      result = described_class.new(setting: 'backup').call

      expect(result).to be_a(Hash)
      expect(result['title']).to be_present
    end

    it 'resolves multi-word settings via camelize' do
      result = described_class.new(setting: 'system_security').call

      expect(result).to be_a(Hash)
    end

    it 'returns nil for an unknown setting (no matching constant)' do
      expect(described_class.new(setting: 'nonexistent').call).to be_nil
    end

    it 'returns nil for a setting whose constant is not a Surveys::Base subclass' do
      stub_const('Surveys::Foo::Survey', Class.new) # plain Class, not < Base

      expect(described_class.new(setting: 'foo').call).to be_nil
    end

    it 'passes sensor_name through to the Survey instance' do
      result = described_class.new(setting: 'sensor', sensor_name: 'inverter_power').call

      # Title shows the human-readable description, the SOLECTRUS sensor name
      # moves to the description line.
      expect(result['title']).to eq(
        'default' => 'Total PV generation',
        'de' => 'Gesamte PV-Erzeugung',
      )
      expect(result['description']).to eq('INVERTER_POWER')
    end

    it 'returns nil for a sensor setting with a missing sensor_name' do
      expect(described_class.new(setting: 'sensor').call).to be_nil
    end

    it 'returns nil for a sensor setting with an unknown sensor_name' do
      expect(described_class.new(setting: 'sensor', sensor_name: 'nonexistent').call).to be_nil
    end
  end
end
