RSpec.describe SensorRegistry do
  describe '.unit_for' do
    it 'returns unit for known sensor' do
      expect(described_class.unit_for('inverter_power')).to eq('W')
    end

    it 'returns percentage for battery_soc' do
      expect(described_class.unit_for('battery_soc')).to eq('%')
    end

    it 'returns empty string for unknown sensor' do
      expect(described_class.unit_for('unknown')).to eq('')
    end
  end

  describe '.sources_for' do
    it 'returns sources for known sensor' do
      expect(described_class.sources_for('inverter_power')).to include('senec', 'mqtt')
    end

    it 'returns empty array for unknown sensor' do
      expect(described_class.sources_for('unknown')).to eq([])
    end
  end

  describe '.group_for' do
    it 'returns group for inverter sensor' do
      expect(described_class.group_for('inverter_power')).to eq(:inverter)
    end

    it 'returns group for battery sensor' do
      expect(described_class.group_for('battery_soc')).to eq(:battery)
    end

    it 'returns nil for unknown sensor' do
      expect(described_class.group_for('unknown')).to be_nil
    end
  end

  describe '.sensors_in_group' do
    it 'returns sensors for inverter group' do
      expect(described_class.sensors_in_group(:inverter)).to include('inverter_power')
    end

    it 'returns empty array for unknown group' do
      expect(described_class.sensors_in_group(:unknown)).to eq([])
    end
  end

  describe '.valid?' do
    it 'returns true for known sensor' do
      expect(described_class.valid?('inverter_power')).to be true
    end

    it 'returns false for unknown sensor' do
      expect(described_class.valid?('unknown')).to be false
    end
  end
end
