RSpec.describe ConfigurationImporter do
  subject(:importer) { described_class.new(stack_reader) }

  let(:stack_reader) { StackReader.new(compose_path:, env_path:) }
  let(:scenario_path) { Rails.root.join('spec/fixtures/scenarios', scenario) }
  let(:compose_path) { scenario_path.join('compose.yaml') }
  let(:env_path) { scenario_path.join('.env') }

  before { with_config_yaml }

  context 'with senec3 scenario' do
    let(:scenario) { 'senec3' }

    it 'returns a hash with setting data' do
      expect(importer.result).to include(:system, :dashboard, :postgresql, :influxdb, :redis, :watchtower,
                                         :sensors, :devices)
    end

    describe 'system data' do
      subject(:system) { importer.result[:system] }

      it { is_expected.to include('timezone' => 'Europe/Berlin') }
      it { is_expected.to include('installation_date' => '2020-01-01') }

      it 'does not include dashboard fields' do
        expect(system.keys).not_to include('admin_password', 'secret_key_base')
      end
    end

    describe 'dashboard data' do
      subject(:dashboard) { importer.result[:dashboard] }

      it { is_expected.to include('admin_password' => 'secret') }
      it { is_expected.to include('secret_key_base') }
      it { is_expected.to include('image') }
    end

    describe 'postgresql data' do
      subject(:postgresql) { importer.result[:postgresql] }

      it 'includes password' do
        expect(postgresql).to include('password' => 'my-secret-db-password')
      end

      it 'includes image' do
        expect(postgresql).to include('image')
      end
    end

    describe 'influxdb data' do
      subject(:influxdb) { importer.result[:influxdb] }

      it 'includes influxdb settings without prefix' do
        expect(influxdb).to include(
          'password' => 'ExAmPl3PA55W0rD',
          'org' => 'solectrus',
          'bucket' => 'solectrus',
        )
      end

      it 'excludes absent influxdb fields' do
        expect(influxdb).not_to have_key('token')
      end

      it 'includes image' do
        expect(influxdb).to include('image')
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

      it 'sets type and name' do
        expect(devices.first).to include(type: 'inverter', name: 'SENEC')
      end
    end

    describe 'sensor data' do
      subject(:sensors) { importer.result[:sensors] }

      it 'includes non-empty sensor mappings with lowercase keys' do
        expect(sensors).to include(
          'inverter_power' => 'SENEC:inverter_power',
          'inverter_power_1' => 'SENEC:mpp1_power',
          'inverter_power_2' => 'SENEC:mpp2_power',
          'inverter_power_3' => 'SENEC:mpp3_power',
          'house_power' => 'SENEC:house_power',
          'grid_import_power' => 'SENEC:grid_power_plus',
          'grid_export_power' => 'SENEC:grid_power_minus',
          'battery_charging_power' => 'SENEC:bat_power_plus',
          'battery_discharging_power' => 'SENEC:bat_power_minus',
          'battery_soc' => 'SENEC:bat_fuel_charge',
          'case_temp' => 'SENEC:case_temp',
          'system_status' => 'SENEC:current_state',
          'system_status_ok' => 'SENEC:current_state_ok',
          'grid_export_limit' => 'SENEC:power_ratio',
        )
      end

      it 'excludes empty sensor mappings' do
        expect(sensors.keys).not_to include(
          'wallbox_power',
          'inverter_power_4',
          'inverter_power_5',
          'heatpump_power',
          'car_battery_soc',
        )
      end
    end

    describe '#import!' do
      subject(:config) { importer.import! }

      it 'returns a Configuration' do
        expect(config).to be_a(Configuration)
      end

      it 'persists system settings' do
        expect(config.system).to include('timezone' => 'Europe/Berlin')
      end

      it 'persists the inverter device' do
        inverters = config.devices_of('inverter')
        expect(inverters.size).to eq(1)
        expect(inverters.first.data).to include('battery_vendor' => 'senec3')
      end

      it 'persists sensor settings' do
        expect(config.sensors).to include('inverter_power' => 'SENEC:inverter_power')
      end
    end
  end

  context 'with with_unknown scenario' do
    let(:scenario) { 'with_unknown' }

    describe '#import!' do
      subject(:config) { importer.import! }

      it 'still imports managed data' do
        expect(config.system).to include('timezone' => 'Europe/Berlin')
      end
    end
  end

  context 'with with_traefik_and_backup scenario' do
    let(:scenario) { 'with_traefik_and_backup' }

    describe 'reverse_proxy data' do
      subject(:reverse_proxy) { importer.result[:reverse_proxy] }

      it 'detects traefik as reverse proxy' do
        expect(reverse_proxy).to include(
          'enabled' => true,
          'app_domain' => 'solar.example.com',
        )
      end
    end

    describe 'backup data' do
      subject(:backup) { importer.result[:backup] }

      it 'detects backup services' do
        expect(backup).to include(
          'enabled' => true,
          'aws_access_key_id' => 'AKIAEXAMPLE',
          'aws_secret_access_key' => 'secret123',
          'aws_region' => 'eu-central-1',
          'aws_bucket' => 'my-backup-bucket',
        )
      end
    end

    describe '#import!' do
      subject(:config) { importer.import! }

      it 'persists reverse_proxy settings' do
        expect(config.reverse_proxy).to include(
          'enabled' => true,
          'app_domain' => 'solar.example.com',
        )
      end

      it 'persists backup settings' do
        expect(config.backup).to include(
          'enabled' => true,
          'aws_bucket' => 'my-backup-bucket',
        )
      end
    end
  end
end
