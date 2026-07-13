RSpec.describe Export::Env::Mqtt do
  subject(:env) { Export::Env.new(Configuration.current).to_s }

  # mqtt-collector reads MQTT_PORT via `env.fetch('MQTT_PORT')` — no default.
  # A missing variable is not a silent fallback, it crash-loops the container,
  # which is why the survey field is mandatory and the port is always exported.
  before do
    with_config_yaml(
      'sensors' => { 'house_power' => { 'source' => 'mqtt', 'measurement' => 'm', 'field' => 'f' } },
      'mqtt' => { 'mqtt_host' => 'broker.local', 'mqtt_port' => '1884' },
    )
  end

  it 'exports the configured port' do
    expect(env).to include('MQTT_PORT=1884')
  end

  it 'passes MQTT_PORT through to the collector' do
    yaml = Export::Compose.new(Configuration.current).to_yaml
    expect(yaml).to match(/^\s*- MQTT_PORT$/)
  end
end
