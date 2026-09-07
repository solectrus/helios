RSpec.describe Export::Services::ForecastCollector do
  subject(:environment) do
    compose = YAML.safe_load(Export::Compose.new(Configuration.current).to_yaml)
    compose.dig('services', 'forecast-collector', 'environment')
  end

  def configure(forecast)
    with_config_yaml(
      'system' => { 'installation_date' => '2024-01-15' },
      'sensors' => { 'inverter_power_forecast' => { 'source' => 'forecast' } },
      'forecast' => forecast,
    )
  end

  context 'with forecast.solar' do
    before do
      configure('forecast' => 'forecast.solar', 'forecast_latitude' => '51.3',
                'forecast_longitude' => '7.5', 'forecast_solar_apikey' => 'key')
    end

    it 'emits the coordinates and the provider key' do
      expect(environment).to include('FORECAST_PROVIDER', 'FORECAST_LATITUDE', 'FORECAST_SOLAR_APIKEY')
    end
  end

  # A provider name HELIOS does not know (imported from a newer collector)
  # still exports the shared vars; nothing provider-specific is invented.
  context 'with an unknown provider' do
    before do
      configure('forecast' => 'something-new', 'forecast_latitude' => '51.3', 'forecast_longitude' => '7.5')
    end

    it 'emits the shared vars only' do
      expect(environment).to include('FORECAST_PROVIDER', 'FORECAST_LATITUDE', 'FORECAST_LONGITUDE')
      expect(environment.grep(/APIKEY|SOLCAST|PVNODE/)).to be_empty
    end
  end
end
