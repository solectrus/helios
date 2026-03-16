RSpec.describe ConfigurationImporter do
  subject(:importer) { described_class.new(compose_path:, env_path:) }

  let(:scenario_path) { Rails.root.join('spec/fixtures/scenarios', scenario) }
  let(:compose_path) { scenario_path.join('compose.yaml') }
  let(:env_path) { scenario_path.join('.env') }

  context 'with senec3 scenario' do
    let(:scenario) { 'senec3' }
    let(:result) { importer.result }

    it 'returns a Configuration' do
      expect(result).to be_a(Configuration)
    end

    describe 'system chapter' do
      subject { result.chapter('system') }

      it { is_expected.to include('timezone' => 'Europe/Berlin') }
      it { is_expected.to include('installation_date' => '2020-01-01') }
    end

    describe 'inverter chapter' do
      subject(:inverters) { result.chapters_of_kind('inverter') }

      it 'detects exactly one SENEC V3 inverter' do
        expect(inverters.size).to eq(1)
      end

      it 'maps SENEC_ADAPTER=local to battery_vendor senec3' do
        expect(inverters.first.data).to include('battery_vendor' => 'senec3')
      end

      it 'imports SENEC connection settings' do
        expect(inverters.first.data).to include(
          'senec_host' => '192.168.178.42',
          'senec_schema' => 'https',
          'senec_language' => 'de',
          'senec_interval' => '5',
        )
      end
    end

    describe 'sensors chapter' do
      subject(:sensors) { result.chapter('sensors') }

      it 'imports non-empty sensor mappings' do
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

      it 'skips empty sensor mappings' do
        expect(sensors.keys).not_to include(
          'INFLUX_SENSOR_WALLBOX_POWER',
          'INFLUX_SENSOR_INVERTER_POWER_4',
          'INFLUX_SENSOR_INVERTER_POWER_5',
          'INFLUX_SENSOR_HEATPUMP_POWER',
          'INFLUX_SENSOR_CAR_BATTERY_SOC',
        )
      end
    end

    describe 'absent device chapters' do
      it { expect(result.chapters_of_kind('wallbox')).to be_empty }
      it { expect(result.chapters_of_kind('battery')).to be_empty }
      it { expect(result.chapters_of_kind('heatpump')).to be_empty }
      it { expect(result.chapters_of_kind('car')).to be_empty }
      it { expect(result.chapters_of_kind('consumer')).to be_empty }
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
end
