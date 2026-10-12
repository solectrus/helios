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

  describe '.payload_type_for' do
    it 'returns a number for a sensor with a unit' do
      expect(described_class.payload_type_for('inverter_power')).to eq('float')
      expect(described_class.payload_type_for('battery_soc')).to eq('float')
    end

    it 'returns a yes/no answer for a boolean sensor' do
      expect(described_class.payload_type_for('wallbox_car_connected')).to eq('boolean')
    end

    it 'returns the type of each car sensor' do
      expect(described_class.payload_type_for('car_odometer')).to eq('float')
      expect(described_class.payload_type_for('car_connected_3')).to eq('boolean')
      expect(described_class.payload_type_for('car_longitude_5')).to eq('float')
    end

    it 'returns text for a unit-less sensor that is not boolean' do
      expect(described_class.payload_type_for('system_status')).to eq('string')
    end

    it 'returns nothing for an unknown sensor, so a stored type stands' do
      expect(described_class.payload_type_for('unknown')).to be_nil
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

    it 'puts car 1 without a number and the other cars with one into a group per car' do
      expect(described_class.sensors_in_group('car_1')).to eq(
        %w[car_battery_soc car_odometer car_range car_connected car_latitude car_longitude],
      )
      expect(described_class.group_for('car_range_5').to_s).to eq('car_5')
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
