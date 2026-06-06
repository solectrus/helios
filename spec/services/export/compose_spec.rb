RSpec.describe Export::Compose do
  subject(:yaml) { described_class.new(Configuration.current).to_yaml }

  # An unmanaged collector adopted from a legacy stack that passed the InfluxDB
  # target through .env via bare `- INFLUX_HOST` entries (older SOLECTRUS compose
  # style). HELIOS suppresses INFLUX_HOST/PORT/SCHEMA from .env on a local stack,
  # so these bare entries would otherwise resolve to nothing at runtime.
  let(:unmanaged) do
    {
      '_unmanaged' => {
        'services' => {
          'tibber-collector' => {
            'image' => 'ghcr.io/solectrus/tibber-collector:latest',
            'environment' => [
              'TZ',
              'INFLUX_HOST',
              'INFLUX_PORT',
              'INFLUX_SCHEMA',
              'INFLUX_ORG',
              'INFLUX_TOKEN=${INFLUX_TOKEN_WRITE}',
              'TIBBER_TOKEN',
            ],
          },
        },
      },
    }
  end

  context 'with a local InfluxDB stack' do
    before { with_config_yaml(unmanaged) }

    it 'bakes the local InfluxDB host/port/schema into the unmanaged service' do
      expect(yaml).to include('- INFLUX_HOST=influxdb')
      expect(yaml).to include('- INFLUX_PORT=8086')
      expect(yaml).to include('- INFLUX_SCHEMA=http')
    end

    it 'leaves other passthroughs bare (still resolved from .env)' do
      expect(yaml).to match(/^\s*- INFLUX_ORG$/)
      expect(yaml).to match(/^\s*- TIBBER_TOKEN$/)
    end

    it 'leaves no bare INFLUX_HOST that would raise KeyError at container start' do
      expect(yaml).not_to match(/^\s*- INFLUX_HOST$/)
      expect(yaml).not_to match(/^\s*- INFLUX_PORT$/)
      expect(yaml).not_to match(/^\s*- INFLUX_SCHEMA$/)
    end
  end

  context 'when in collectors_only mode (external InfluxDB supplied via .env)' do
    before { with_config_yaml(unmanaged.deep_merge('deployment' => { 'mode' => 'collectors_only' })) }

    it 'keeps the passthrough bare so it reads the external target from .env' do
      expect(yaml).to match(/^\s*- INFLUX_HOST$/)
      expect(yaml).not_to include('- INFLUX_HOST=influxdb')
    end
  end

  # A stale passthrough of a service that has since become managed. compose has
  # one entry per service name, so without the guard whichever is written last
  # would decide — and unmanaged services are written last in full mode.
  context 'when a managed service of the same name is configured' do
    before { with_config_yaml(unmanaged.merge('tibber' => { 'token' => 'from-the-survey' })) }

    it 'emits the service exactly once' do
      expect(yaml.scan(/^ {2}tibber-collector:/).size).to eq(1)
    end

    it 'lets the managed service win over the stale passthrough' do
      expect(yaml).to match(/^\s*- INFLUX_MEASUREMENT=\$\{INFLUX_MEASUREMENT_PRICES\}$/)
      expect(yaml).not_to include('Unmanaged service (preserved from existing installation)')
    end
  end
end
