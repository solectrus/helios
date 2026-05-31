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

    it 'returns true for mini-survey IDs' do
      expect(described_class.valid?('system_security')).to be true
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

    it 'slices the parent singleton down to the mini-survey keys' do
      config = described_class.current
      config.update('system', { 'timezone' => 'UTC', 'admin_password' => 'secret' })

      expect(config.setting_data('system_general')).to eq({ 'timezone' => 'UTC' })
      expect(config.setting_data('system_security')).to eq({ 'admin_password' => 'secret' })
    end

    it 'merges borrowed fields in from their foreign section' do
      config = described_class.current
      config.update('system', { 'admin_password' => 'secret' })
      config.update('dashboard', { 'lockup_codeword' => 'open-sesame', 'ui_theme' => 'dark' })

      expect(config.setting_data('system_security')).to eq(
        { 'admin_password' => 'secret', 'lockup_codeword' => 'open-sesame' },
      )
    end

    it 'synthesises read-only storage data from StoragePaths' do
      dir = with_config_yaml('postgresql' => { 'volume_path' => '/mnt/disk1/postgres' })

      data = described_class.current.setting_data('storage')

      expect(data['postgresql']).to eq('/mnt/disk1/postgres')
      expect(data['influxdb']).to eq("#{dir}/influxdb")
    end
  end

  describe '#update with a read-only setting' do
    it 'refuses to write storage' do
      config = described_class.current

      expect { config.update('storage', { 'postgresql' => '/evil' }) }
        .to raise_error(ArgumentError, /read-only/)
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

  describe '#prune_shadowed_shelly_devices!' do
    it 'removes devices whose measurement another collector writes' do
      with_config_yaml(
        'shelly' => {
          'connection' => 'local',
          'devices' => [
            { 'name' => 'oven', 'host' => 'oven.local', 'measurement' => 'oven' },
            { 'name' => 'attic', 'host' => 'attic.local', 'measurement' => 'attic' },
          ],
        },
        'sensors' => { 'custom_power_01' => { 'source' => 'mqtt', 'measurement' => 'oven' } },
      )
      config = described_class.current

      expect(config.prune_shadowed_shelly_devices!).to be(true)
      expect(config.shelly_devices.pluck('measurement')).to eq(%w[attic])
    end

    it 'keeps devices consumed by an external sensor' do
      with_config_yaml(
        'shelly' => { 'devices' => [{ 'name' => 'oven', 'measurement' => 'oven' }] },
        'sensors' => { 'custom_power_01' => { 'source' => 'external', 'measurement' => 'oven' } },
      )
      expect(described_class.current.prune_shadowed_shelly_devices!).to be(false)
    end

    # A heatpump whose total power comes from a Shelly plug and whose heating
    # power comes from MQTT shares the `heatpump` measurement across two
    # collectors writing different fields. The Shelly device must survive.
    it 'keeps a device still consumed by a Shelly sensor sharing the measurement' do
      with_config_yaml(
        'shelly' => {
          'connection' => 'local',
          'devices' => [{ 'name' => 'heatpump', 'host' => 'hp.local', 'measurement' => 'heatpump' }],
        },
        'sensors' => {
          'heatpump_power' => { 'source' => 'shelly', 'measurement' => 'heatpump', 'field' => 'power' },
          'heatpump_heating_power' => { 'source' => 'mqtt', 'measurement' => 'heatpump', 'field' => 'heating_power' },
        },
      )
      config = described_class.current

      expect(config.prune_shadowed_shelly_devices!).to be(false)
      expect(config.shelly_devices.pluck('measurement')).to eq(%w[heatpump])
    end
  end

  describe '#update_sensor pruning shadowed Shelly devices' do
    it 'drops a Shelly device once its measurement moves to another source' do
      with_config_yaml(
        'shelly' => {
          'connection' => 'local',
          'devices' => [{ 'name' => 'oven', 'host' => 'oven.local', 'measurement' => 'oven' }],
        },
      )
      config = described_class.current

      config.update_sensor('custom_power_01', { 'source' => 'mqtt', 'measurement' => 'oven', 'field' => 'power' })

      expect(config.shelly_devices).to be_empty
    end

    it 'leaves Shelly devices intact when the saved sensor does not shadow them' do
      with_config_yaml(
        'shelly' => {
          'connection' => 'local',
          'devices' => [{ 'name' => 'oven', 'host' => 'oven.local', 'measurement' => 'oven' }],
        },
      )
      config = described_class.current

      config.update_sensor('custom_power_01', { 'source' => 'mqtt', 'measurement' => 'attic', 'field' => 'power' })

      expect(config.shelly_devices.pluck('measurement')).to eq(%w[oven])
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

    it 'includes shelly when standalone devices are configured without a shelly sensor' do
      devices = [{ 'name' => 'Oven', 'host' => 'oven.local', 'measurement' => 'oven' }]
      with_config_yaml(
        'shelly' => { 'connection' => 'local', 'devices' => devices },
        'sensors' => { 'custom_power_01' => { 'source' => 'mqtt', 'measurement' => 'oven' } },
      )
      expect(described_class.current.active_sources).to eq(%w[mqtt shelly])
    end

    it 'omits shelly when the section is set without devices or sensors' do
      with_config_yaml('shelly' => { 'connection' => 'local' })
      expect(described_class.current.active_sources).to be_empty
    end

    it 'lists configured collector sections in collectors_only mode even without sensors' do
      with_config_yaml(
        'deployment' => { 'mode' => ConfigSchema::MODE_COLLECTORS_ONLY },
        'senec' => { 'version' => '4', 'host' => '10.0.0.10' },
        'shelly' => { 'connection' => 'cloud' },
      )
      expect(described_class.current.active_sources).to eq(%w[shelly senec])
    end

    it 'drops device-collector sources in dashboard_only mode' do
      with_config_yaml(
        'deployment' => { 'mode' => ConfigSchema::MODE_DASHBOARD_ONLY },
        'sensors' => {
          'inverter_power' => { 'source' => 'external' },
          'custom_power_01' => { 'source' => 'shelly', 'shelly_host' => 'shelly.local' },
          'inverter_power_forecast' => { 'source' => 'forecast' },
        },
      )
      expect(described_class.current.active_sources).to eq(%w[forecast external])
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

    it 'merges a mini-survey ID into the parent singleton, leaving siblings intact' do
      config = described_class.current
      config.update('system', { 'admin_password' => 'secret', 'timezone' => 'Europe/Berlin' })
      config.update('system_security', { 'admin_password' => 'new-secret' })

      expect(config.system).to eq(
        { 'admin_password' => 'new-secret', 'timezone' => 'Europe/Berlin' },
      )
    end

    it 'drops mini-survey keys that are not in the patch (cleared by the user)' do
      config = described_class.current
      config.update('system', { 'admin_password' => 'secret', 'app_host' => 'old.example' })
      config.update('system_network', {})

      expect(config.system).to eq({ 'admin_password' => 'secret' })
    end

    it 'removes the singleton entirely once the last mini-survey key is cleared' do
      config = described_class.current
      config.update('system_security', { 'admin_password' => 'pw' })
      config.update('system_security', {})

      expect(config.system).to be_empty
    end

    it 'routes a borrowed field into its foreign section, not the survey section' do
      config = described_class.current
      config.update('dashboard', { 'ui_theme' => 'dark' })
      config.update('system_security', { 'admin_password' => 'pw', 'lockup_codeword' => 'open-sesame' })

      expect(config.system).to eq({ 'admin_password' => 'pw' })
      expect(config.dashboard).to eq({ 'ui_theme' => 'dark', 'lockup_codeword' => 'open-sesame' })
    end

    it 'removes a borrowed field from its section when cleared' do
      config = described_class.current
      config.update('dashboard', { 'ui_theme' => 'dark' })
      config.update('system_security', { 'admin_password' => 'pw', 'lockup_codeword' => 'x' })
      config.update('system_security', { 'admin_password' => 'pw', 'lockup_codeword' => '' })

      expect(config.dashboard).to eq({ 'ui_theme' => 'dark' })
    end

    it 'stores the reverse-proxy trusted_proxy_ranges under dashboard' do
      config = described_class.current
      config.update('reverse_proxy',
                    { 'app_domain' => 'example.com', 'trusted_proxy_ranges' => '10.0.0.0/8' })

      expect(config.reverse_proxy).to eq({ 'app_domain' => 'example.com' })
      expect(config.dashboard).to eq({ 'trusted_proxy_ranges' => '10.0.0.0/8' })
      expect(config.setting_data('reverse_proxy')).to eq(
        { 'app_domain' => 'example.com', 'trusted_proxy_ranges' => '10.0.0.0/8' },
      )
    end

    it 'translates software channel tokens into the registry image URLs' do
      config = described_class.current
      config.update('software', {
                      'service_channels' => { 'dashboard' => 'develop' },
                      'update_interval' => '3600',
                    })

      expect(config.dashboard.image).to eq('ghcr.io/solectrus/solectrus:develop')
      expect(config.system.update_interval).to eq('3600')
    end

    it 'preserves sibling keys in service singletons when updating software channels' do
      config = described_class.current
      config.update('dashboard', { 'co2_emission_factor' => '401' })
      config.update('senec', { 'version' => '4' })
      config.update('software', { 'service_channels' => { 'dashboard' => 'latest' } })

      expect(config.dashboard.co2_emission_factor).to eq('401')
      expect(config.senec.version).to eq('4')
    end

    it 'strips unknown fields from sections on save' do
      config = described_class.current
      config.update('system', { 'timezone' => 'UTC', 'unknown_field' => 'stale' })

      reloaded = described_class.current
      expect(reloaded.system).to include('timezone' => 'UTC')
      expect(reloaded.system).not_to have_key('unknown_field')
    end

    context 'when switching to dashboard_only mode' do
      before do
        with_config_yaml(
          'shelly' => { 'connection' => 'local' },
          'senec' => { 'version' => '4', 'host' => '10.0.0.10' },
          'mqtt' => { 'mqtt_host' => 'broker', 'mappings' => [{ 'topic' => 't' }] },
          'forecast' => { 'forecast' => 'forecast.solar' },
          'sensors' => {
            'inverter_power' => { 'source' => 'senec' },
            'custom_power_01' => { 'source' => 'shelly', 'shelly_host' => 'shelly.local',
                                   'measurement' => 'fridge', 'field' => 'power' },
            'inverter_power_forecast' => { 'source' => 'forecast' },
          },
        )
        described_class.current.update('deployment',
                                       { 'mode' => ConfigSchema::MODE_DASHBOARD_ONLY })
      end

      it 'drops device-collector sections' do
        reloaded = described_class.current
        expect(reloaded.shelly).to be_empty
        expect(reloaded.senec).to be_empty
        expect(reloaded.mqtt).to be_empty
      end

      it 'preserves the forecast section' do
        expect(described_class.current.forecast.forecast).to eq('forecast.solar')
      end

      it 'rewrites device-source sensors to external, keeping mapping' do
        config = described_class.current
        custom = config.sensor_config('custom_power_01')
        expect(custom.source).to eq('external')
        expect(custom.measurement).to eq('fridge')
        expect(custom.field).to eq('power')
        expect(custom).not_to have_key('shelly_host')
      end

      it 'leaves forecast sensors alone' do
        expect(described_class.current.sensor_config('inverter_power_forecast').source).to eq('forecast')
      end
    end

    context 'when switching to collectors_only mode' do
      before do
        with_config_yaml(
          'reverse_proxy' => { 'app_domain' => 'example.com' },
          'backup' => { 'aws_bucket' => 'my-bucket' },
          'postgresql' => { 'password' => 'keep-me' },
          'shelly' => { 'connection' => 'cloud' },
          'sensors' => { 'inverter_power' => { 'source' => 'senec' } },
          'influxdb' => {
            'org' => 'solectrus', 'bucket' => 'solectrus',
            'publish_port' => true, 'host_port' => '8086', 'use_hashed_tokens' => true
          },
        )
        described_class.current.update('deployment',
                                       { 'mode' => ConfigSchema::MODE_COLLECTORS_ONLY })
      end

      it 'drops dashboard-only sections' do
        reloaded = described_class.current
        expect(reloaded.reverse_proxy).to be_empty
        expect(reloaded.backup).to be_empty
      end

      it 'drops sensors (canonicalization happens on the remote dashboard host)' do
        expect(described_class.current.enabled_sensors).to be_empty
      end

      it 'preserves source-config sections (used as raw mappings here)' do
        expect(described_class.current.shelly.connection).to eq('cloud')
      end

      it 'leaves auto-generated database passwords intact' do
        expect(described_class.current.postgresql.password).to eq('keep-me')
      end

      it 'strips local-container-only fields from the influxdb section' do
        reloaded = described_class.current.influxdb
        expect(reloaded).not_to have_key('publish_port')
        expect(reloaded).not_to have_key('host_port')
        expect(reloaded).not_to have_key('use_hashed_tokens')
        expect(reloaded.org).to eq('solectrus')
      end
    end

    context 'when switching back from collectors_only to full mode' do
      before do
        with_config_yaml(
          'deployment' => { 'mode' => ConfigSchema::MODE_COLLECTORS_ONLY },
          'influxdb' => {
            'host' => 'old.example.com', 'port' => '443', 'schema' => 'https',
            'org' => 'solectrus', 'bucket' => 'solectrus', 'token_admin' => 'tok'
          },
        )
        described_class.current.update('deployment', { 'mode' => ConfigSchema::MODE_FULL })
      end

      it 'strips the external InfluxDB connection fields' do
        reloaded = described_class.current.influxdb
        expect(reloaded).not_to have_key('host')
        expect(reloaded).not_to have_key('port')
        expect(reloaded).not_to have_key('schema')
      end

      it 'preserves auto-generated InfluxDB fields' do
        reloaded = described_class.current.influxdb
        expect(reloaded.org).to eq('solectrus')
        expect(reloaded.bucket).to eq('solectrus')
        expect(reloaded.token_admin).to eq('tok')
      end
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

  describe '#incomplete_influxdb?' do
    it 'returns false in full mode regardless of host' do
      with_config_yaml('influxdb' => { 'org' => 'solectrus' })
      expect(described_class.current.incomplete_influxdb?).to be false
    end

    it 'returns true in collectors_only mode without a host' do
      with_config_yaml(
        'deployment' => { 'mode' => ConfigSchema::MODE_COLLECTORS_ONLY },
        'influxdb' => { 'org' => 'solectrus', 'bucket' => 'solectrus' },
      )
      expect(described_class.current.incomplete_influxdb?).to be true
    end

    it 'returns false in collectors_only mode once a host is set' do
      with_config_yaml(
        'deployment' => { 'mode' => ConfigSchema::MODE_COLLECTORS_ONLY },
        'influxdb' => { 'host' => 'influx.example.com', 'org' => 'solectrus' },
      )
      expect(described_class.current.incomplete_influxdb?).to be false
    end
  end

  describe '#incomplete_system_general?' do
    it 'returns true in full mode without an installation date' do
      expect(described_class.current.incomplete_system_general?).to be true
    end

    it 'returns false once an installation date is set' do
      with_config_yaml('system' => { 'installation_date' => '2024-01-15' })
      expect(described_class.current.incomplete_system_general?).to be false
    end

    it 'returns false in collectors_only mode even without a date' do
      with_config_yaml('deployment' => { 'mode' => ConfigSchema::MODE_COLLECTORS_ONLY })
      expect(described_class.current.incomplete_system_general?).to be false
    end

    it 'surfaces via setting_incomplete?(system_general) when the date is missing' do
      expect(described_class.current.setting_incomplete?('system_general')).to be true
    end

    it 'clears setting_incomplete?(system_general) once the date is set' do
      with_config_yaml('system' => { 'installation_date' => '2024-01-15' })
      expect(described_class.current.setting_incomplete?('system_general')).to be false
    end
  end

  describe '#configuration_complete?' do
    it 'returns false when setup is not completed yet' do
      with_config_yaml('system' => { 'installation_date' => '2024-01-15' })
      expect(described_class.current.configuration_complete?).to be false
    end

    it 'returns false when a sensor is configured but the installation date is missing' do
      with_config_yaml(
        'senec' => { 'version' => '4' },
        'sensors' => { 'inverter_power' => { 'source' => 'senec' } },
      )
      expect(described_class.current.configuration_complete?).to be false
    end

    it 'returns true once setup is done and no setting is incomplete' do
      with_config_yaml(
        'system' => { 'installation_date' => '2024-01-15' },
        'senec' => { 'version' => '4' },
        'sensors' => { 'inverter_power' => { 'source' => 'senec' } },
      )
      expect(described_class.current.configuration_complete?).to be true
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
        'deployment' => { 'mode' => ConfigSchema::MODE_COLLECTORS_ONLY },
        'senec' => { 'version' => '4', 'host' => '10.0.0.10' },
      )
      expect(described_class.current.setup_completed?).to be true
    end

    it 'returns false in collectors_only mode without any active source' do
      with_config_yaml('deployment' => { 'mode' => ConfigSchema::MODE_COLLECTORS_ONLY })
      expect(described_class.current.setup_completed?).to be false
    end
  end

  describe '#visible_settings' do
    it 'omits ingest_settings by default in full mode' do
      with_config_yaml
      expect(described_class.current.visible_settings).not_to include('ingest_settings')
    end

    it 'inserts ingest_settings right after influxdb when a balcony sensor activates it' do
      with_config_yaml(
        'sensors' => { 'inverter_power_2' => { 'source' => 'shelly', 'is_balcony' => true } },
      )
      settings = described_class.current.visible_settings
      expect(settings[settings.index('influxdb') + 1]).to eq('ingest_settings')
    end

    it 'never surfaces ingest in collectors_only mode (no local InfluxDB to write to)' do
      with_config_yaml(
        'deployment' => { 'mode' => ConfigSchema::MODE_COLLECTORS_ONLY },
        'sensors' => { 'inverter_power_2' => { 'source' => 'shelly', 'is_balcony' => true } },
      )
      expect(described_class.current.visible_settings).not_to include('ingest_settings')
    end

    it 'appends ingest_settings in dashboard_only mode (no influxdb to anchor against)' do
      with_config_yaml(
        'deployment' => { 'mode' => ConfigSchema::MODE_DASHBOARD_ONLY },
        'sensors' => { 'inverter_power_2' => { 'source' => 'external', 'is_balcony' => true } },
      )
      settings = described_class.current.visible_settings
      expect(settings.last).to eq('ingest_settings')
      expect(settings).not_to include('influxdb')
    end
  end

  describe '#advanced_groups' do
    it 'returns every group with at least one visible setting in full mode' do
      with_config_yaml
      expect(described_class.current.advanced_groups).to eq(
        'installation' => %w[deployment software system_general],
        'access' => %w[system_network influxdb dashboard_network reverse_proxy system_security],
        'data' => %w[storage],
        'dashboard' => %w[dashboard_co2 dashboard_theme],
      )
    end

    it 'keeps influxdb and system_security in the access group in collectors_only mode' do
      with_config_yaml('deployment' => { 'mode' => ConfigSchema::MODE_COLLECTORS_ONLY })
      expect(described_class.current.advanced_groups.fetch('access')).to eq(
        %w[influxdb system_security],
      )
    end

    it 'surfaces the data group with ingest_settings when a balcony sensor activates it' do
      with_config_yaml(
        'sensors' => { 'inverter_power_2' => { 'source' => 'shelly', 'is_balcony' => true } },
      )
      expect(described_class.current.advanced_groups.fetch('data')).to eq(
        %w[ingest_settings storage],
      )
    end

    it 'keeps only the installation and access groups in collectors_only mode' do
      with_config_yaml('deployment' => { 'mode' => ConfigSchema::MODE_COLLECTORS_ONLY })
      expect(described_class.current.advanced_groups.keys).to contain_exactly(
        'installation',
        'access',
      )
    end

    it 'keeps the data group with storage in dashboard_only mode without a balcony sensor' do
      with_config_yaml('deployment' => { 'mode' => ConfigSchema::MODE_DASHBOARD_ONLY })
      expect(described_class.current.advanced_groups.fetch('data')).to eq(%w[storage])
    end
  end
end
