RSpec.describe 'Import::ConfigurationImporter house power exclusions' do
  subject(:importer) { Import::ConfigurationImporter.new(stack_reader) }

  before { with_config_yaml }

  let(:dashboard_env) { {} }
  let(:services) { { 'dashboard' => { 'environment' => dashboard_env } } }
  let(:raw_env) { {} }
  let(:stack_reader) do
    instance_double(
      Import::StackReader,
      raw_env: raw_env,
      raw_compose: { 'services' => services },
      services: services,
      stack_dir: '/srv/solectrus',
    ).tap do |double|
      allow(double).to receive(:service) { |name| services[name] }
    end
  end

  def import_and_load
    importer.import!
    YAML.safe_load_file(Configuration.path, permitted_classes: [Date])
  end

  context 'with an external sensor flagged for exclusion' do
    let(:dashboard_env) do
      {
        'INFLUX_SENSOR_HEATPUMP_POWER' => 'pv:heatpump_power',
        'INFLUX_EXCLUDE_FROM_HOUSE_POWER' => 'HEATPUMP_POWER',
      }
    end

    it 'persists exclude_from_house_power on the sensor' do
      expect(import_and_load.dig('sensors', 'heatpump_power')).to include(
        'source' => 'external',
        'exclude_from_house_power' => true,
      )
    end
  end

  context 'with multiple sensors flagged for exclusion' do
    let(:dashboard_env) do
      {
        'INFLUX_SENSOR_HEATPUMP_POWER' => 'pv:heatpump_power',
        'INFLUX_SENSOR_CUSTOM_POWER_01' => 'pv:fridge',
        'INFLUX_SENSOR_CUSTOM_POWER_02' => 'pv:dishwasher',
        'INFLUX_EXCLUDE_FROM_HOUSE_POWER' => 'HEATPUMP_POWER, CUSTOM_POWER_02',
      }
    end

    it 'flags only the listed sensors' do
      sensors = import_and_load['sensors']
      expect(sensors['heatpump_power']).to include('exclude_from_house_power' => true)
      expect(sensors['custom_power_02']).to include('exclude_from_house_power' => true)
      expect(sensors['custom_power_01']).not_to include('exclude_from_house_power')
    end
  end

  context 'without INFLUX_EXCLUDE_FROM_HOUSE_POWER' do
    let(:dashboard_env) { { 'INFLUX_SENSOR_HEATPUMP_POWER' => 'pv:heatpump_power' } }

    it 'leaves the sensor without the flag' do
      expect(import_and_load.dig('sensors', 'heatpump_power')).not_to include('exclude_from_house_power')
    end
  end
end
