RSpec.describe SensorMappings do
  describe '.default_measurement' do
    it 'returns SENEC for senec source with known sensor' do
      expect(described_class.default_measurement('inverter_power', 'senec')).to eq('SENEC')
    end

    it 'returns SENEC for senec source with unknown sensor' do
      expect(described_class.default_measurement('unknown', 'senec')).to eq('SENEC')
    end

    it 'returns forecast for forecast source' do
      expect(described_class.default_measurement('inverter_power_forecast', 'forecast')).to eq('forecast')
    end

    it 'returns forecast for forecast source with unknown sensor' do
      expect(described_class.default_measurement('unknown', 'forecast')).to eq('forecast')
    end

    it 'returns sensor_name for other sources' do
      expect(described_class.default_measurement('heatpump_power', 'shelly')).to eq('heatpump_power')
    end
  end

  describe '.default_field' do
    it 'returns mapped field for senec source' do
      expect(described_class.default_field('inverter_power', 'senec')).to eq('inverter_power')
    end

    it 'returns mapped field for senec mpp1' do
      expect(described_class.default_field('inverter_power_1', 'senec')).to eq('mpp1_power')
    end

    it 'returns watt for forecast source' do
      expect(described_class.default_field('inverter_power_forecast', 'forecast')).to eq('watt')
    end

    it 'returns power for shelly source' do
      expect(described_class.default_field('heatpump_power', 'shelly')).to eq('power')
    end

    it 'returns value for mqtt source' do
      expect(described_class.default_field('inverter_power', 'mqtt')).to eq('value')
    end
  end

  describe '.mapping_for' do
    def build_config(hash)
      Configuration::Data.wrap(hash)
    end

    it 'returns mapping string with defaults' do
      config = build_config('source' => 'senec')

      expect(described_class.mapping_for('inverter_power', config)).to eq('SENEC:inverter_power')
    end

    it 'uses custom measurement when provided' do
      config = build_config('source' => 'mqtt', 'measurement' => 'MyDevice', 'field' => 'power')

      expect(described_class.mapping_for('inverter_power', config)).to eq('MyDevice:power')
    end

    it 'returns nil for blank source' do
      config = build_config({})

      expect(described_class.mapping_for('inverter_power', config)).to be_nil
    end
  end
end
