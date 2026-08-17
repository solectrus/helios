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

    {
      %w[heatpump_power shelly] => 'heatpump',
      %w[inverter_power mqtt] => 'inverter',
      %w[inverter_power_2 external] => 'inverter_2',
      %w[house_power mqtt] => 'house',
      %w[case_temp mqtt] => 'case',
      %w[custom_power_03 shelly] => 'custom_03',
    }.each do |(sensor, source), expected|
      it "returns '#{expected}' for #{sensor} with #{source} source" do
        expect(described_class.default_measurement(sensor, source)).to eq(expected)
      end
    end

    it 'falls back to sensor_name for unknown sensors' do
      expect(described_class.default_measurement('unknown', 'mqtt')).to eq('unknown')
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

    it 'returns temp (not temperature) for outdoor_temp_forecast on forecast source' do
      expect(described_class.default_field('outdoor_temp_forecast', 'forecast')).to eq('temp')
    end

    {
      %w[heatpump_power shelly] => 'power',
      %w[inverter_power mqtt] => 'power',
      %w[inverter_power_2 external] => 'power',
      %w[battery_soc mqtt] => 'soc',
      %w[grid_import_power mqtt] => 'import_power',
      %w[wallbox_car_connected mqtt] => 'connected',
      %w[case_temp mqtt] => 'temperature',
      %w[custom_power_03 shelly] => 'power',
    }.each do |(sensor, source), expected|
      it "returns '#{expected}' for #{sensor} with #{source} source" do
        expect(described_class.default_field(sensor, source)).to eq(expected)
      end
    end

    it 'falls back to value for unknown sensors' do
      expect(described_class.default_field('unknown', 'mqtt')).to eq('value')
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

    it 'maps a forecast outdoor_temp_forecast to the temp field by default' do
      config = build_config('source' => 'forecast', 'measurement' => 'forecast')

      expect(described_class.mapping_for('outdoor_temp_forecast', config)).to eq('forecast:temp')
    end
  end

  # Line protocol escapes `,`, `=` and space, so a name carrying one of them
  # survives a round trip. Only what HELIOS itself splits on, plus the
  # underscore InfluxDB reserves, cannot work.
  describe '.valid_measurement?' do
    it 'accepts a plain name' do
      expect(described_class).to be_valid_measurement('SENEC')
    end

    it 'accepts non-ASCII letters' do
      expect(described_class).to be_valid_measurement('Lüfter_Garage')
    end

    it 'accepts a space, which line protocol escapes' do
      expect(described_class).to be_valid_measurement('PQ Inverter')
    end

    it 'accepts an equals sign, which line protocol escapes' do
      expect(described_class).to be_valid_measurement('a=b')
    end

    it 'rejects a comma, which splits INFLUX_MEASUREMENT' do
      expect(described_class).not_to be_valid_measurement('PQ,Inverter')
    end

    it 'rejects a colon, which splits the measurement:field mapping' do
      expect(described_class).not_to be_valid_measurement('PQ:Inverter')
    end

    it 'rejects a leading underscore, which InfluxDB reserves' do
      expect(described_class).not_to be_valid_measurement('_inverter')
    end

    it 'accepts an underscore that does not lead' do
      expect(described_class).to be_valid_measurement('pq_inverter')
    end

    it 'rejects a blank name' do
      expect(described_class).not_to be_valid_measurement('')
    end
  end

  describe '.valid_field?' do
    it 'accepts a plain name' do
      expect(described_class).to be_valid_field('power')
    end

    it 'accepts a colon, which the mapping split tolerates in a field' do
      expect(described_class).to be_valid_field('a:b')
    end

    it 'rejects a leading underscore, which InfluxDB reserves' do
      expect(described_class).not_to be_valid_field('_power')
    end
  end
end
