RSpec.describe 'Import::ConfigurationImporter car sensors' do
  subject(:importer) { Import::ConfigurationImporter.new(stack_reader) }

  before { with_config_yaml }

  let(:services) { { 'dashboard' => { 'environment' => dashboard_env } } }
  let(:stack_reader) do
    instance_double(
      Import::StackReader,
      raw_env: dashboard_env,
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

  context 'with the variables of car 1 under its number' do
    let(:dashboard_env) do
      {
        'INFLUX_SENSOR_CAR_ODOMETER_1' => 'car:odometer',
        'INFLUX_SENSOR_CAR_CONNECTED_1' => 'car:connected',
      }
    end

    it 'imports them as car 1, which exports without the number' do
      config = import_and_load

      expect(config['sensors'].keys).to contain_exactly('car_odometer', 'car_connected')
      expect(config['sensors']['car_odometer']).to include('measurement' => 'car', 'field' => 'odometer')
      expect(config.to_yaml).not_to include('CAR_ODOMETER_1')
    end
  end

  context 'with car 1 both with and without its number' do
    let(:dashboard_env) do
      {
        'INFLUX_SENSOR_CAR_BATTERY_SOC' => 'old:soc',
        'INFLUX_SENSOR_CAR_BATTERY_SOC_1' => 'car:battery_soc',
      }
    end

    it 'takes the numbered variable, as the dashboard does' do
      expect(import_and_load.dig('sensors', 'car_battery_soc')).to include(
        'measurement' => 'car', 'field' => 'battery_soc',
      )
    end
  end

  context 'with a second car' do
    let(:dashboard_env) do
      {
        'INFLUX_SENSOR_CAR_RANGE_2' => 'tesla:range',
        'INFLUX_SENSOR_CAR_LATITUDE_2' => 'tesla:latitude',
      }
    end

    it 'imports its numbered sensors' do
      expect(import_and_load['sensors']).to include(
        'car_range_2' => hash_including('measurement' => 'tesla', 'field' => 'range'),
        'car_latitude_2' => hash_including('measurement' => 'tesla', 'field' => 'latitude'),
      )
    end
  end
end
