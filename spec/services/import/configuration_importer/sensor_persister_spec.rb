RSpec.describe Import::ConfigurationImporter::SensorPersister do
  describe '#persist!' do
    # The fourth channel of a Pro 4PM. Without it, the sensor lands on
    # `external` and no longer follows the device.
    it 'hands a mapping on power_d to the Shelly device' do
      persister = described_class.new(
        sensors_data: { 'custom_power_01' => 'Pumps:power_d' },
        devices: [{ name: 'Pumps', data: { 'data_source' => 'shelly' } }],
        enabled_collectors: [:shelly],
        mqtt_mappings: [],
      )
      config = Configuration.current

      persister.persist!(config)

      expect(config.sensor_config('custom_power_01').to_h)
        .to include('source' => 'shelly', 'measurement' => 'Pumps', 'field' => 'power_d')
    end
  end
end
