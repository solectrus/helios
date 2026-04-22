RSpec.describe Import::ConfigurationImporter::LegacySensorAdapter do
  describe '.synthesize' do
    it 'returns an empty hash when no legacy markers are set' do
      expect(described_class.synthesize('INFLUX_SENSOR_HOUSE_POWER' => 'pv:house_power')).to eq({})
    end

    it 'synthesizes sensor mappings from INFLUX_MEASUREMENT_PV' do
      synthesized = described_class.synthesize('INFLUX_MEASUREMENT_PV' => 'pv')

      expect(synthesized).to include(
        'house_power' => 'pv:house_power',
        'grid_import_power' => 'pv:grid_power_plus',
        'grid_export_power' => 'pv:grid_power_minus',
        'battery_charging_power' => 'pv:bat_power_plus',
        'battery_soc' => 'pv:bat_fuel_charge',
        'inverter_power' => 'pv:inverter_power',
      )
    end

    it 'synthesizes inverter_power_forecast from INFLUX_MEASUREMENT_FORECAST' do
      synthesized = described_class.synthesize('INFLUX_MEASUREMENT_FORECAST' => 'fc')

      expect(synthesized).to include('inverter_power_forecast' => 'fc:watt')
    end

    it 'does not overwrite an explicit INFLUX_SENSOR_* entry' do
      env = {
        'INFLUX_MEASUREMENT_PV' => 'pv',
        'INFLUX_SENSOR_HOUSE_POWER' => 'custom:house',
      }

      expect(described_class.synthesize(env)).not_to have_key('house_power')
    end

    it 'skips sensors whose measurement var is absent' do
      synthesized = described_class.synthesize('INFLUX_MEASUREMENT_FORECAST' => 'fc')

      expect(synthesized.keys).not_to include('house_power', 'inverter_power')
    end
  end
end
