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

  describe 'write behavior' do
    before do
      with_config_yaml(
        'sensors' => {
          'house_power' => {
            'source' => 'mqtt', 'measurement' => 'm', 'field' => 'f',
            'mqtt_payload_type' => 'integer',
            'mqtt_aggregate_interval' => '60', 'mqtt_dedup' => true, 'mqtt_heartbeat_interval' => '900'
          },
        },
        'mqtt' => {
          'mqtt_host' => 'broker.local', 'mqtt_port' => '1883',
          'mappings' => [
            { 'topic' => 'leak/state', 'measurement' => 'Leak', 'field' => 'detected',
              'type' => 'boolean', 'dedup' => true },
          ]
        },
      )
    end

    it 'exports the options of a sensor mapping' do
      expect(env).to include(
        'MAPPING_0_AGGREGATE_INTERVAL=60',
        'MAPPING_0_DEDUP=true',
        'MAPPING_0_HEARTBEAT_INTERVAL=900',
      )
    end

    # The heartbeat stays out when it is not set, so the collector applies its
    # own default of 60 seconds.
    it 'exports the options of a standalone topic' do
      expect(env).to include('MAPPING_1_DEDUP=true')
      expect(env).not_to include('MAPPING_1_HEARTBEAT_INTERVAL')
    end

    it 'passes the new variables through to the collector' do
      yaml = Export::Compose.new(Configuration.current).to_yaml
      expect(yaml).to match(/^\s*- MAPPING_0_AGGREGATE_INTERVAL$/)
      expect(yaml).to match(/^\s*- MAPPING_1_DEDUP$/)
    end
  end

  # A mapping without a topic calculates its value from mappings it reads by
  # their MAPPING_X_NAME. Order does not matter, the collector sorts formulas
  # by dependency itself.
  describe 'names and calculated mappings' do
    before do
      with_config_yaml(
        'sensors' => {
          'house_power' => {
            'source' => 'mqtt', 'measurement' => 'PV', 'field' => 'house_power',
            'mqtt_topic' => 'h/p', 'mqtt_payload_type' => 'integer',
            'mqtt_name' => 'house_power', 'mqtt_max_age' => '300'
          },
        },
        'mqtt' => {
          'mqtt_host' => 'broker.local', 'mqtt_port' => '1883',
          'mappings' => [
            { 'name' => 'base_load', 'formula' => '{house_power} - 100',
              'measurement' => 'Household', 'field' => 'base_load', 'type' => 'integer' },
            { 'topic' => 'w/p', 'name' => 'wallbox', 'type' => 'integer', 'skip_write' => true },
          ]
        },
      )
    end

    it 'names a sensor mapping and limits how long a formula may use it' do
      expect(env).to include('MAPPING_0_NAME=house_power', 'MAPPING_0_MAX_AGE=300')
    end

    it 'writes a calculated mapping without a topic' do
      expect(env).to include("MAPPING_1_FORMULA='{house_power} - 100'", 'MAPPING_1_NAME=base_load')
      expect(env).not_to include('MAPPING_1_TOPIC')
    end

    # SKIP_WRITE keeps the value in memory for formulas, so the collector needs
    # no destination for it.
    it 'writes a mapping that is kept in memory only' do
      expect(env).to include('MAPPING_2_SKIP_WRITE=true', 'MAPPING_2_NAME=wallbox')
      expect(env).not_to include('MAPPING_2_MEASUREMENT')
    end
  end

  # An option switched off is an option not set: false is the collector's
  # default, so writing it would only add noise.
  it 'omits deduplication when it is switched off' do
    with_config_yaml(
      'sensors' => {
        'house_power' => {
          'source' => 'mqtt', 'measurement' => 'm', 'field' => 'f', 'mqtt_dedup' => false
        },
      },
      'mqtt' => { 'mqtt_host' => 'broker.local', 'mqtt_port' => '1883' },
    )

    expect(env).not_to include('MAPPING_0_DEDUP')
  end
end
