RSpec.describe 'Import::ConfigurationImporter and the PV forecast band' do
  subject(:importer) { Import::ConfigurationImporter.new(stack_reader) }

  before { with_config_yaml }

  let(:plan) { 'nowcast' }
  let(:dashboard_env) { { 'INFLUX_SENSOR_INVERTER_POWER_FORECAST' => 'Forecast:watt' } }
  let(:forecast_env) do
    { 'FORECAST_PROVIDER' => 'pvnode', 'PVNODE_SITE_ID' => 'site-42', 'PVNODE_APIKEY' => 'k', 'PVNODE_PAID' => plan }
  end
  let(:services) do
    {
      'dashboard' => { 'image' => 'ghcr.io/solectrus/solectrus:latest', 'environment' => dashboard_env },
      'forecast-collector' => {
        'image' => 'ghcr.io/solectrus/forecast-collector:latest', 'environment' => forecast_env
      },
    }
  end
  let(:stack_reader) do
    instance_double(
      Import::StackReader,
      raw_env: dashboard_env.merge(forecast_env),
      raw_compose: { 'services' => services },
      services: services,
      stack_dir: '/srv/solectrus',
    ).tap { |double| allow(double).to receive(:service) { |name| services[name] } }
  end

  def imported_sensors
    importer.import!
    YAML.safe_load_file(Configuration.path, permitted_classes: [Date])['sensors']
  end

  context 'with pvnode, a site ID and the Plus plan' do
    it 'enables both sensors of the band' do
      expect(imported_sensors).to include(
        'inverter_power_forecast_min' => { 'source' => 'forecast' },
        'inverter_power_forecast_max' => { 'source' => 'forecast' },
      )
    end
  end

  context 'with a band sensor the stack maps itself' do
    let(:dashboard_env) { super().merge('INFLUX_SENSOR_INVERTER_POWER_FORECAST_MIN' => 'band:low') }

    it 'keeps that mapping' do
      expect(imported_sensors['inverter_power_forecast_min']).to include('measurement' => 'band', 'field' => 'low')
    end
  end

  context 'with the Light plan' do
    let(:plan) { 'true' }

    it 'enables nothing' do
      expect(imported_sensors.keys).not_to include(*SensorRegistry::PVNODE_V2_SENSORS)
    end
  end
end
