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

  describe '.singleton?' do
    it 'returns true for singleton types' do
      expect(described_class.singleton?('system')).to be true
      expect(described_class.singleton?('forecast')).to be true
      expect(described_class.singleton?('senec')).to be true
    end

    it 'returns false for unknown types' do
      expect(described_class.singleton?('unknown')).to be false
    end
  end

  describe '.valid?' do
    it 'returns true for valid settings' do
      expect(described_class.valid?('system')).to be true
      expect(described_class.valid?('senec')).to be true
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

  describe '#setting_data' do
    it 'returns data for singleton' do
      config = described_class.current
      config.update('system', { 'timezone' => 'Europe/Berlin' })

      expect(config.setting_data('system')).to eq({ 'timezone' => 'Europe/Berlin' })
    end
  end

  describe 'mqtt_topics CRUD' do
    let(:basic_topic) do
      { 'topic' => 'sensors/power', 'measurement' => 'house', 'field' => 'power', 'type' => 'integer' }
    end

    it 'returns an empty list when no topics are configured' do
      expect(described_class.current.mqtt_topics).to eq([])
    end

    it 'persists added topics under mqtt.mappings' do
      config = described_class.current
      config.add_mqtt_topic(basic_topic)

      expect(config.mqtt_topics).to contain_exactly(basic_topic)
    end

    it 'returns a single topic by index' do
      config = described_class.current
      config.add_mqtt_topic(basic_topic)

      expect(config.mqtt_topic(0)).to eq(basic_topic)
    end

    it 'updates an existing topic by index' do
      config = described_class.current
      config.add_mqtt_topic(basic_topic)
      config.update_mqtt_topic(0, basic_topic.merge('field' => 'energy'))

      expect(config.mqtt_topic(0)['field']).to eq('energy')
    end

    it 'leaves the list untouched when updating an unknown index' do
      config = described_class.current
      expect { config.update_mqtt_topic(99, basic_topic) }.not_to(change { config.mqtt_topics })
    end

    it 'removes a topic by index' do
      config = described_class.current
      config.add_mqtt_topic(basic_topic)
      config.remove_mqtt_topic(0)

      expect(config.mqtt_topics).to be_empty
    end

    it 'drops the mappings key entirely once empty' do
      config = described_class.current
      config.add_mqtt_topic(basic_topic)
      config.remove_mqtt_topic(0)

      expect(YAML.load_file(described_class.path)['mqtt']).not_to include('mappings')
    end

    it 'strips unknown keys on save' do
      config = described_class.current
      config.add_mqtt_topic(basic_topic.merge('attacker' => 'value'))

      expect(config.mqtt_topic(0)).not_to include('attacker')
    end
  end

  describe 'shelly_devices CRUD' do
    let(:basic_device) do
      { 'name' => 'Heat pump', 'host' => 'shelly-hp.local', 'measurement' => 'shelly_hp' }
    end

    it 'returns an empty list when no devices are configured' do
      expect(described_class.current.shelly_devices).to eq([])
    end

    it 'persists added devices under shelly.devices' do
      config = described_class.current
      config.add_shelly_device(basic_device)

      expect(config.shelly_devices).to contain_exactly(basic_device)
    end

    it 'returns a single device by index' do
      config = described_class.current
      config.add_shelly_device(basic_device)

      expect(config.shelly_device(0)).to eq(basic_device)
    end

    it 'updates an existing device by index' do
      config = described_class.current
      config.add_shelly_device(basic_device)
      config.update_shelly_device(0, basic_device.merge('measurement' => 'shelly_hp_2'))

      expect(config.shelly_device(0)['measurement']).to eq('shelly_hp_2')
    end

    it 'leaves the list untouched when updating an unknown index' do
      config = described_class.current
      expect { config.update_shelly_device(99, basic_device) }.not_to(change { config.shelly_devices })
    end

    it 'removes a device by index' do
      config = described_class.current
      config.add_shelly_device(basic_device)
      config.remove_shelly_device(0)

      expect(config.shelly_devices).to be_empty
    end

    it 'drops the devices key entirely once empty' do
      config = described_class.current
      config.update('shelly', { 'connection' => 'local' })
      config.add_shelly_device(basic_device)
      config.remove_shelly_device(0)

      expect(YAML.load_file(described_class.path)['shelly']).not_to include('devices')
    end

    it 'strips unknown keys on save' do
      config = described_class.current
      config.add_shelly_device(basic_device.merge('attacker' => 'value'))

      expect(config.shelly_device(0)).not_to include('attacker')
    end

    it 'preserves the cloud-mode device_id field' do
      config = described_class.current
      config.add_shelly_device(
        { 'name' => 'Plug', 'device_id' => 'shellyplug-123', 'measurement' => 'plug' },
      )

      expect(config.shelly_device(0)).to include('device_id' => 'shellyplug-123')
    end
  end

  describe '#active_sources' do
    it 'lists sources used by at least one sensor' do
      with_config_yaml('sensors' => { 'inverter_power' => { 'source' => 'senec' } })
      expect(described_class.current.active_sources).to eq(%w[senec])
    end

    it 'includes mqtt when standalone mappings are configured without an MQTT sensor' do
      mappings = [{ 'topic' => 't', 'measurement' => 'm', 'field' => 'f' }]
      with_config_yaml('mqtt' => { 'mqtt_host' => 'broker', 'mappings' => mappings })
      expect(described_class.current.active_sources).to eq(%w[mqtt])
    end

    it 'omits mqtt when only the broker is set without mappings or sensors' do
      with_config_yaml('mqtt' => { 'mqtt_host' => 'broker' })
      expect(described_class.current.active_sources).to be_empty
    end

    it 'lists configured collector sections in collectors_only mode even without sensors' do
      with_config_yaml(
        'system' => { 'mode' => ConfigSchema::MODE_COLLECTORS_ONLY },
        'senec' => { 'version' => '4', 'host' => '10.0.0.10' },
        'shelly' => { 'connection' => 'cloud' },
      )
      expect(described_class.current.active_sources).to eq(%w[senec shelly])
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

    it 'persists to YAML file' do
      config = described_class.current
      config.update('system', { 'timezone' => 'UTC' })

      reloaded = described_class.current
      expect(reloaded.system).to eq({ 'timezone' => 'UTC' })
    end

    it 'strips unknown fields from sections on save' do
      config = described_class.current
      config.update('system', { 'timezone' => 'UTC', 'unknown_field' => 'stale' })

      reloaded = described_class.current
      expect(reloaded.system).to include('timezone' => 'UTC')
      expect(reloaded.system).not_to have_key('unknown_field')
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

  describe 'sensor management' do
    describe '#update_sensor' do
      it 'adds a sensor with config' do
        config = described_class.current
        config.update_sensor('inverter_power', { 'source' => 'senec' })

        expect(config.sensor_enabled?('inverter_power')).to be true
        expect(config.sensor_config('inverter_power').source).to eq('senec')
      end
    end

    describe '#remove_sensor' do
      it 'removes a sensor' do
        config = described_class.current
        config.update_sensor('inverter_power', { 'source' => 'senec' })
        config.remove_sensor('inverter_power')

        expect(config.sensor_enabled?('inverter_power')).to be false
      end
    end

    describe '#enabled_sensors' do
      it 'returns only valid sensor names' do
        config = described_class.current
        config.update_sensor('inverter_power', { 'source' => 'senec' })
        config.update_sensor('house_power', { 'source' => 'senec' })

        expect(config.enabled_sensors).to contain_exactly('inverter_power', 'house_power')
      end
    end

    describe '#sensors_with_source' do
      it 'filters sensors by source' do
        config = described_class.current
        config.update_sensor('inverter_power', { 'source' => 'senec' })
        config.update_sensor('heatpump_power', { 'source' => 'shelly', 'shelly_host' => '1.2.3.4' })

        senec_sensors = config.sensors_with_source('senec')
        expect(senec_sensors.keys).to eq(['inverter_power'])
      end
    end

    describe '#auto_enable_senec_sensors!' do
      it 'activates every SENEC-capable sensor that is not yet configured' do
        config = described_class.current

        activated = config.auto_enable_senec_sensors!

        expected = SensorRegistry::SENSORS.each_key
                                          .select { |n| SensorRegistry.sources_for(n).include?('senec') }
        expect(activated).to match_array(expected)
        expected.each do |name|
          expect(config.sensor_config(name).source).to eq('senec')
        end
      end

      it 'does not touch sensors that already have a different source' do
        config = described_class.current
        config.update_sensor('wallbox_power', { 'source' => 'mqtt', 'mqtt_topic' => 'wb/p' })

        activated = config.auto_enable_senec_sensors!

        expect(activated).not_to include('wallbox_power')
        expect(config.sensor_config('wallbox_power').source).to eq('mqtt')
      end

      it 'does not touch sensors that are already SENEC' do
        config = described_class.current
        config.update_sensor('inverter_power', { 'source' => 'senec' })

        activated = config.auto_enable_senec_sensors!

        expect(activated).not_to include('inverter_power')
      end

      it 'returns an empty array when nothing changes' do
        config = described_class.current
        config.auto_enable_senec_sensors!

        expect(config.auto_enable_senec_sensors!).to eq([])
      end

      it 'ignores non-SENEC-capable sensors' do
        config = described_class.current
        config.auto_enable_senec_sensors!

        expect(config.sensor_enabled?('heatpump_power')).to be false
        expect(config.sensor_enabled?('car_battery_soc')).to be false
      end
    end
  end

  describe '#mqtt_required?' do
    it 'returns false when no sensors use MQTT' do
      config = described_class.current
      config.update_sensor('inverter_power', { 'source' => 'senec' })

      expect(config.mqtt_required?).to be false
    end

    it 'returns true when a sensor uses MQTT' do
      config = described_class.current
      config.update_sensor('car_battery_soc', { 'source' => 'mqtt', 'mqtt_topic' => 'car/soc' })

      expect(config.mqtt_required?).to be true
    end
  end

  describe '#senec_required?' do
    it 'returns true when a sensor uses SENEC' do
      config = described_class.current
      config.update_sensor('inverter_power', { 'source' => 'senec' })

      expect(config.senec_required?).to be true
    end

    it 'returns false when no sensors use SENEC' do
      config = described_class.current
      config.update_sensor('heatpump_power', { 'source' => 'shelly' })

      expect(config.senec_required?).to be false
    end
  end

  describe '#shelly_required?' do
    it 'returns true when a sensor uses Shelly' do
      config = described_class.current
      config.update_sensor('heatpump_power', { 'source' => 'shelly', 'shelly_host' => '1.2.3.4' })

      expect(config.shelly_required?).to be true
    end
  end

  describe '#effective_sensor_mappings' do
    it 'returns mappings for enabled sensors' do
      config = described_class.current
      config.update_sensor('inverter_power', { 'source' => 'senec' })

      expect(config.effective_sensor_mappings).to include(
        'inverter_power' => 'SENEC:inverter_power',
      )
    end
  end

  describe '#excluded_from_house_power' do
    it 'returns sensor names flagged for exclusion' do
      config = described_class.current
      config.update_sensor('custom_power_01', {
                             'source' => 'shelly',
                             'shelly_host' => '1.2.3.4',
                             'exclude_from_house_power' => true,
                           })

      expect(config.excluded_from_house_power).to eq(['CUSTOM_POWER_01'])
    end
  end

  describe '#setup_completed?' do
    it 'returns false when no sensors are configured' do
      config = described_class.current
      expect(config.setup_completed?).to be false
    end

    it 'returns true when at least one sensor is configured' do
      config = described_class.current
      config.update_sensor('inverter_power', { 'source' => 'senec' })

      expect(config.setup_completed?).to be true
    end

    it 'returns true in collectors_only mode when an active source is configured' do
      with_config_yaml(
        'system' => { 'mode' => ConfigSchema::MODE_COLLECTORS_ONLY },
        'senec' => { 'version' => '4', 'host' => '10.0.0.10' },
      )
      expect(described_class.current.setup_completed?).to be true
    end

    it 'returns false in collectors_only mode without any active source' do
      with_config_yaml('system' => { 'mode' => ConfigSchema::MODE_COLLECTORS_ONLY })
      expect(described_class.current.setup_completed?).to be false
    end
  end
end
