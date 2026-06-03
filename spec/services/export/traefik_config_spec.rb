RSpec.describe Export::TraefikConfig do
  subject(:output) { described_class.new(configuration).to_s }

  before { with_config_yaml }

  let(:configuration) do
    config = Configuration.current
    config.update('system', { 'app_host' => 'demo.example.com', 'timezone' => 'Europe/Berlin' })
    config.update('deployment', { 'mode' => 'dashboard_only' })
    config.update('reverse_proxy', { 'bind_ip' => '10.0.0.5' })
    config
  end
  let(:document) { YAML.safe_load(output) }

  it 'routes the dashboard on the bare app_host to the bind IP' do
    expect(document.dig('http', 'routers', 'solectrus-dashboard', 'rule')).to eq('Host(`demo.example.com`)')
    expect(document.dig('http', 'services', 'solectrus-dashboard', 'loadBalancer', 'servers', 0, 'url'))
      .to eq('http://10.0.0.5:3000')
  end

  it 'routes influxdb on a subdomain to its host port' do
    expect(document.dig('http', 'routers', 'solectrus-influxdb', 'rule')).to eq('Host(`influxdb.demo.example.com`)')
    expect(document.dig('http', 'services', 'solectrus-influxdb', 'loadBalancer', 'servers', 0, 'url'))
      .to eq('http://10.0.0.5:8086')
  end

  it 'emits placeholders for the user-specific certResolver and middlewares' do
    router = document.dig('http', 'routers', 'solectrus-dashboard')
    expect(router['tls']['certResolver']).to eq('CHANGE_ME')
    expect(router['middlewares']).to eq(['CHANGE_ME'])
  end

  it 'starts with an explanatory header comment' do
    expect(output).to start_with('# Traefik dynamic configuration')
  end
end
