RSpec.describe Export::Services::SenecCollector do
  let(:env) { Export::Env.new(Configuration.current).to_s }
  let(:environment) do
    compose = YAML.safe_load(Export::Compose.new(Configuration.current).to_yaml)
    compose.dig('services', 'senec-collector', 'environment')
  end

  before do
    with_config_yaml(
      'system' => { 'installation_date' => '2024-01-15' },
      'senec' => { 'host' => 'senec.local', 'measurement' => measurement },
      'sensors' => { 'inverter_power' => { 'source' => 'senec', 'measurement' => measurement,
                                           'field' => 'inverter_power' } },
    )
  end

  context 'with the default measurement' do
    let(:measurement) { 'SENEC' }

    it 'exports it' do
      expect(env).to include('INFLUX_MEASUREMENT_SENEC=SENEC')
    end
  end

  # The collector reads INFLUX_MEASUREMENT (defaulting to 'SENEC'), so a
  # measurement configured in the survey has to arrive under that name — else
  # the collector keeps writing to SENEC while the sensor mappings already
  # point at the new measurement, and the readings land nowhere.
  context 'with a custom measurement' do
    let(:measurement) { 'MYSENEC' }

    it 'exports the configured measurement' do
      expect(env).to include('INFLUX_MEASUREMENT_SENEC=MYSENEC')
    end

    it 'maps it onto the name the collector reads' do
      expect(environment).to include('INFLUX_MEASUREMENT=${INFLUX_MEASUREMENT_SENEC}')
    end

    it 'does not pass the .env-only name to the collector' do
      expect(environment).not_to include('INFLUX_MEASUREMENT_SENEC')
    end
  end
end
