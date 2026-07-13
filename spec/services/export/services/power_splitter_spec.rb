RSpec.describe Export::Services::PowerSplitter do
  subject(:environment) do
    compose = YAML.safe_load(Export::Compose.new(Configuration.current).to_yaml)
    compose.dig('services', 'power-splitter', 'environment')
  end

  # A custom consumer excluded from house power: the splitter subtracts it from
  # house_power before dividing the grid draw across the consumers
  # (power-splitter/lib/splitter.rb#custom_power_total). Reaching the dashboard
  # but not the splitter would leave the split with a wrong denominator.
  let(:sensors) do
    {
      'grid_import_power' => { 'source' => 'senec', 'measurement' => 'SENEC', 'field' => 'grid_power_plus' },
      'house_power' => { 'source' => 'senec', 'measurement' => 'SENEC', 'field' => 'house_power' },
      'wallbox_power' => { 'source' => 'mqtt', 'measurement' => 'Wallbox', 'field' => 'power' },
      'custom_power_01' => {
        'source' => 'mqtt', 'measurement' => 'Oven', 'field' => 'power',
        'exclude_from_house_power' => excluded
      },
    }
  end

  before do
    with_config_yaml(
      'system' => { 'installation_date' => '2024-01-15' },
      'sensors' => sensors,
      'mqtt' => { 'mqtt_host' => 'broker.local', 'mqtt_port' => '1883' },
    )
  end

  context 'with a consumer excluded from house power' do
    let(:excluded) { true }

    it 'passes the exclusion through to the splitter' do
      expect(environment).to include('INFLUX_EXCLUDE_FROM_HOUSE_POWER')
    end
  end

  context 'without any exclusion' do
    let(:excluded) { false }

    it 'omits the variable' do
      expect(environment).not_to include('INFLUX_EXCLUDE_FROM_HOUSE_POWER')
    end
  end
end
