RSpec.describe Export::Services::Influxdb do
  subject(:environment) do
    compose = YAML.safe_load(Export::Compose.new(Configuration.current).to_yaml)
    compose.dig('services', 'influxdb', 'environment')
  end

  before do
    with_config_yaml(
      'system' => { 'installation_date' => '2024-01-15' },
      'influxdb' => { 'publish_port' => publish_port },
    )
  end

  context 'with an exposed InfluxDB' do
    let(:publish_port) { true }

    it 'disables the unauthenticated /metrics endpoint' do
      expect(environment).to include('INFLUXD_METRICS_DISABLED=true')
    end
  end

  context 'with an InfluxDB kept inside the stack' do
    let(:publish_port) { false }

    it 'keeps /metrics for diagnosis' do
      expect(environment).not_to include(a_string_starting_with('INFLUXD_METRICS_DISABLED'))
    end
  end
end
