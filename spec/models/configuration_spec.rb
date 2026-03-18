RSpec.describe Configuration do
  before { with_config_yaml }

  describe '.current' do
    it 'returns a Configuration instance' do
      config = described_class.current
      expect(config).to be_a(described_class)
    end

    it 'reads from config.yaml if it exists' do
      with_config_yaml('system' => { 'timezone' => 'Europe/Berlin' })
      config = described_class.current

      expect(config.system).to eq({ 'timezone' => 'Europe/Berlin' })
    end

    it 'returns empty config when file does not exist' do
      config = described_class.current
      expect(config.system).to eq({})
    end
  end

  describe '.device?' do
    it 'returns true for device types' do
      expect(described_class.device?('inverter')).to be true
      expect(described_class.device?('battery')).to be true
    end

    it 'returns false for singleton types' do
      expect(described_class.device?('system')).to be false
    end
  end

  describe '.singleton?' do
    it 'returns true for singleton types' do
      expect(described_class.singleton?('system')).to be true
      expect(described_class.singleton?('forecast')).to be true
    end

    it 'returns false for device types' do
      expect(described_class.singleton?('inverter')).to be false
    end
  end

  describe '.valid?' do
    it 'returns true for valid settings' do
      expect(described_class.valid?('inverter')).to be true
      expect(described_class.valid?('system')).to be true
    end

    it 'returns false for invalid settings' do
      expect(described_class.valid?('unknown')).to be false
    end
  end

  describe 'singleton accessors' do
    it 'returns empty hash for non-existent singleton' do
      config = described_class.current
      expect(config.system).to eq({})
    end

    it 'returns data for singleton' do
      config = described_class.current
      config.update('system', { 'timezone' => 'Europe/Berlin' })

      expect(config.system).to eq({ 'timezone' => 'Europe/Berlin' })
    end
  end

  describe 'device accessors' do
    it 'returns data for device with name' do
      config = described_class.current
      config.add('inverter', 'Dach Süd', { 'data_source' => 'senec_local' })

      expect(config.inverter('Dach Süd')).to eq(
        { 'data_source' => 'senec_local' },
      )
    end

    it 'returns empty hash for non-existent device name' do
      config = described_class.current
      expect(config.inverter('missing')).to eq({})
    end
  end

  describe '#setting_data' do
    it 'returns data for singleton' do
      config = described_class.current
      config.update('system', { 'timezone' => 'Europe/Berlin' })

      expect(config.setting_data('system')).to eq({ 'timezone' => 'Europe/Berlin' })
    end

    it 'returns data for device with name' do
      config = described_class.current
      config.add('inverter', 'Dach Süd', { 'data_source' => 'senec_local' })

      expect(config.setting_data('inverter', 'Dach Süd')).to eq(
        { 'data_source' => 'senec_local' },
      )
    end
  end

  describe '#update' do
    it 'creates a new singleton entry' do
      config = described_class.current
      config.update('system', { 'timezone' => 'Europe/Berlin' })

      expect(config.system).to eq({ 'timezone' => 'Europe/Berlin' })
    end

    it 'updates existing singleton data' do
      config = described_class.current
      config.update('system', { 'timezone' => 'UTC' })
      config.update('system', { 'timezone' => 'Europe/Berlin', 'mqtt_host' => '192.168.1.44' })

      expect(config.system).to eq(
        { 'timezone' => 'Europe/Berlin', 'mqtt_host' => '192.168.1.44' },
      )
    end

    it 'creates a device entry with name' do
      config = described_class.current
      config.update('inverter', { 'data_source' => 'senec_local' }, name: 'Dach Süd')

      expect(config.inverter('Dach Süd')).to eq(
        { 'data_source' => 'senec_local' },
      )
    end

    it 'persists to YAML file' do
      config = described_class.current
      config.update('system', { 'timezone' => 'UTC' })

      reloaded = described_class.current
      expect(reloaded.system).to eq({ 'timezone' => 'UTC' })
    end
  end

  describe '#configured?' do
    it 'returns false for non-existent setting' do
      config = described_class.current
      expect(config.configured?('system')).to be false
    end

    it 'returns true for setting with data' do
      config = described_class.current
      config.update('system', { 'timezone' => 'UTC' })

      expect(config.configured?('system')).to be true
    end
  end

  describe '#devices_of' do
    it 'returns all devices of a given type' do
      config = described_class.current
      config.add('inverter', 'Dach Süd', { 'data_source' => 'senec_local' })
      config.add('inverter', 'BKW', { 'data_source' => 'mqtt' })
      config.add('wallbox', 'Garage')

      devices = config.devices_of('inverter')
      expect(devices.size).to eq(2)
      expect(devices.map(&:name)).to contain_exactly('Dach Süd', 'BKW')
    end

    it 'returns empty array for no devices' do
      config = described_class.current
      expect(config.devices_of('inverter')).to eq([])
    end
  end

  describe '#add' do
    it 'creates a device entry' do
      config = described_class.current
      config.add('inverter', 'Dach Süd', { 'data_source' => 'senec_local' })

      expect(config.inverter('Dach Süd')).to eq(
        { 'data_source' => 'senec_local' },
      )
    end

    it 'raises error for non-device types' do
      config = described_class.current

      expect do
        config.add('system', 'test')
      end.to raise_error(ArgumentError, /not a device/)
    end
  end

  describe '#remove' do
    it 'removes a device entry' do
      config = described_class.current
      config.add('inverter', 'Dach Süd')
      config.remove('inverter', 'Dach Süd')

      expect(config.inverter('Dach Süd')).to eq({})
    end
  end

  describe '#mqtt_required?' do
    it 'returns false when no devices use MQTT' do
      config = described_class.current
      config.add('inverter', 'PV', { 'data_source' => 'senec_local' })

      expect(config.mqtt_required?).to be false
    end

    it 'returns true when a device uses MQTT as data_source' do
      config = described_class.current
      config.add('inverter', 'PV', { 'data_source' => 'mqtt' })

      expect(config.mqtt_required?).to be true
    end

    it 'returns true when heatpump uses MQTT as power_source' do
      config = described_class.current
      config.add('heatpump', 'HP', { 'power_source' => 'mqtt' })

      expect(config.mqtt_required?).to be true
    end

    it 'returns true when heatpump uses MQTT as details_source' do
      config = described_class.current
      config.add('heatpump', 'HP', { 'details_source' => 'mqtt' })

      expect(config.mqtt_required?).to be true
    end
  end

  describe '#ingest_required?' do
    it 'returns false with single inverter that knows house power' do
      config = described_class.current
      config.add('inverter', 'PV', { 'house_power_known' => true })

      expect(config.ingest_required?).to be false
    end

    it 'returns true with single inverter that does not know house power' do
      config = described_class.current
      config.add('inverter', 'PV', { 'house_power_known' => false })

      expect(config.ingest_required?).to be true
    end

    it 'returns true with multiple inverters' do
      config = described_class.current
      config.add('inverter', 'Dach', { 'house_power_known' => true })
      config.add('inverter', 'BKW', { 'house_power_known' => true })

      expect(config.ingest_required?).to be true
    end

    it 'returns false with no inverters' do
      config = described_class.current

      expect(config.ingest_required?).to be false
    end
  end

  describe '#senec_hosts' do
    it 'returns deduplicated SENEC hosts' do
      config = described_class.current
      config.add(
        'inverter', 'PV',
        { 'data_source' => 'senec_local', 'senec_host' => '192.168.1.42' }
      )
      config.add(
        'battery', 'Akku',
        { 'data_source' => 'senec_local', 'senec_host' => '192.168.1.42' }
      )

      expect(config.senec_hosts).to eq(['192.168.1.42'])
    end

    it 'returns empty array when no SENEC devices' do
      config = described_class.current
      config.add('inverter', 'PV', { 'data_source' => 'mqtt' })

      expect(config.senec_hosts).to eq([])
    end
  end

  describe '#effective_sensor_mappings' do
    it 'merges computed mappings with overrides' do
      config = described_class.current
      config.update(
        'sensors',
        { 'inverter_power' => 'custom:power' },
      )

      expect(config.effective_sensor_mappings).to include(
        'inverter_power' => 'custom:power',
      )
    end
  end

  describe '#setup_completed?' do
    it 'returns false when no config.yaml exists' do
      config = described_class.current
      expect(config.setup_completed?).to be false
    end

    it 'returns true when system timezone is set' do
      config = described_class.current
      config.update('system', { 'timezone' => 'Europe/Berlin' })

      reloaded = described_class.current
      expect(reloaded.setup_completed?).to be true
    end
  end
end
