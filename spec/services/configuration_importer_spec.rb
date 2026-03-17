RSpec.describe ConfigurationImporter do
  subject(:importer) { described_class.new(stack_reader) }

  let(:stack_reader) { StackReader.new(compose_path:, env_path:) }
  let(:scenario_path) { Rails.root.join('spec/fixtures/scenarios', scenario) }
  let(:compose_path) { scenario_path.join('compose.yaml') }
  let(:env_path) { scenario_path.join('.env') }

  context 'with senec3 scenario' do
    let(:scenario) { 'senec3' }

    it 'returns a hash with chapter data' do
      expect(importer.result).to include(:system, :sensors, :devices)
    end

    describe 'system data' do
      subject(:system) { importer.result[:system] }

      it { is_expected.to include('timezone' => 'Europe/Berlin') }
      it { is_expected.to include('installation_date' => '2020-01-01') }

      it 'includes secrets' do
        expect(system).to include(
          'postgres_password' => 'my-secret-db-password',
          'admin_password' => 'secret',
          'influx_password' => 'ExAmPl3PA55W0rD',
          'influx_org' => 'solectrus',
          'influx_bucket' => 'solectrus',
        )
      end

      it 'excludes absent secrets' do
        expect(system).not_to have_key('influx_token')
      end
    end

    describe 'device data' do
      subject(:devices) { importer.result[:devices] }

      it 'detects exactly one SENEC inverter' do
        expect(devices.size).to eq(1)
      end

      it 'maps SENEC_ADAPTER=local to battery_vendor senec3' do
        expect(devices.first[:data]).to include('battery_vendor' => 'senec3')
      end

      it 'includes SENEC connection settings' do
        expect(devices.first[:data]).to include(
          'senec_host' => '192.168.178.42',
          'senec_schema' => 'https',
          'senec_language' => 'de',
          'senec_interval' => '5',
        )
      end

      it 'sets kind and name' do
        expect(devices.first).to include(kind: 'inverter', name: 'SENEC')
      end
    end

    describe 'sensor data' do
      subject(:sensors) { importer.result[:sensors] }

      it 'includes non-empty sensor mappings' do
        expect(sensors).to include(
          'INFLUX_SENSOR_INVERTER_POWER' => 'SENEC:inverter_power',
          'INFLUX_SENSOR_INVERTER_POWER_1' => 'SENEC:mpp1_power',
          'INFLUX_SENSOR_INVERTER_POWER_2' => 'SENEC:mpp2_power',
          'INFLUX_SENSOR_INVERTER_POWER_3' => 'SENEC:mpp3_power',
          'INFLUX_SENSOR_HOUSE_POWER' => 'SENEC:house_power',
          'INFLUX_SENSOR_GRID_IMPORT_POWER' => 'SENEC:grid_power_plus',
          'INFLUX_SENSOR_GRID_EXPORT_POWER' => 'SENEC:grid_power_minus',
          'INFLUX_SENSOR_BATTERY_CHARGING_POWER' => 'SENEC:bat_power_plus',
          'INFLUX_SENSOR_BATTERY_DISCHARGING_POWER' => 'SENEC:bat_power_minus',
          'INFLUX_SENSOR_BATTERY_SOC' => 'SENEC:bat_fuel_charge',
          'INFLUX_SENSOR_CASE_TEMP' => 'SENEC:case_temp',
          'INFLUX_SENSOR_SYSTEM_STATUS' => 'SENEC:current_state',
          'INFLUX_SENSOR_SYSTEM_STATUS_OK' => 'SENEC:current_state_ok',
          'INFLUX_SENSOR_GRID_EXPORT_LIMIT' => 'SENEC:power_ratio',
        )
      end

      it 'excludes empty sensor mappings' do
        expect(sensors.keys).not_to include(
          'INFLUX_SENSOR_WALLBOX_POWER',
          'INFLUX_SENSOR_INVERTER_POWER_4',
          'INFLUX_SENSOR_INVERTER_POWER_5',
          'INFLUX_SENSOR_HEATPUMP_POWER',
          'INFLUX_SENSOR_CAR_BATTERY_SOC',
        )
      end
    end

    describe '#import!' do
      subject(:config) { importer.import! }

      it 'returns a Configuration' do
        expect(config).to be_a(Configuration)
      end

      it 'persists the system chapter' do
        expect(config.chapter('system')).to include('timezone' => 'Europe/Berlin')
      end

      it 'persists the inverter device' do
        inverters = config.chapters_of_kind('inverter')
        expect(inverters.size).to eq(1)
        expect(inverters.first.data).to include('battery_vendor' => 'senec3')
      end

      it 'persists the sensors chapter' do
        expect(config.chapter('sensors')).to include('INFLUX_SENSOR_INVERTER_POWER' => 'SENEC:inverter_power')
      end
    end

    describe '#unmanaged_services' do
      subject { importer.unmanaged_services }

      it { is_expected.to be_empty }
    end

    describe '#unmanaged_env_vars' do
      subject { importer.unmanaged_env_vars }

      it { is_expected.to be_empty }
    end
  end

  context 'with with_unmanaged scenario' do
    let(:scenario) { 'with_unmanaged' }

    describe 'unmanaged services' do
      it 'detects dozzle and nginx as unmanaged' do
        expect(importer.unmanaged_services).to contain_exactly('dozzle', 'nginx')
      end

      it 'preserves raw service configs' do
        services = importer.result[:unmanaged]['services']

        expect(services['dozzle']).to include(
          'image' => 'amir20/dozzle:latest',
          'restart' => 'unless-stopped',
        )
        expect(services['dozzle']['ports']).to include('8082:8080')
      end

      it 'preserves ${VAR} references in service configs' do
        nginx_env = importer.result[:unmanaged]['services']['nginx']['environment']
        expect(nginx_env).to include('NGINX_CUSTOM_SETTING=${MY_CUSTOM_VAR}')
      end

      it 'does not include managed services' do
        services = importer.result[:unmanaged]['services']
        expect(services.keys).not_to include('dashboard', 'postgresql', 'redis', 'influxdb', 'watchtower')
      end
    end

    describe 'unmanaged env vars' do
      it 'detects MY_CUSTOM_VAR as unmanaged' do
        expect(importer.unmanaged_env_vars).to eq(%w[MY_CUSTOM_VAR])
      end

      it 'preserves the raw value' do
        expect(importer.result[:unmanaged]['env_vars']).to eq('MY_CUSTOM_VAR' => 'custom-value')
      end
    end

    describe '#import!' do
      subject(:config) { importer.import! }

      it 'persists unmanaged services' do
        expect(config.unmanaged['services']).to have_key('dozzle')
        expect(config.unmanaged['services']).to have_key('nginx')
      end

      it 'persists unmanaged env vars' do
        expect(config.unmanaged['env_vars']).to eq('MY_CUSTOM_VAR' => 'custom-value')
      end
    end
  end
end
