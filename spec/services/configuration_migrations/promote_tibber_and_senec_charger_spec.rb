RSpec.describe ConfigurationMigrations::PromoteTibberAndSenecCharger do
  subject(:up) { described_class.new.up(data) }

  # Baseline of a stack that satisfies the charger's export gate: a locally
  # queried SENEC battery to steer and a forecast collector to read.
  def base_data(**extra)
    {
      'deployment' => { 'mode' => 'full' },
      'system' => { 'timezone' => 'Europe/Berlin' },
      'influxdb' => { 'org' => 'solectrus', 'bucket' => 'solectrus' },
      'senec' => { 'adapter' => 'local', 'host' => '192.168.178.42', 'schema' => 'https', 'version' => 'v3' },
      'forecast' => { 'forecast' => 'forecast.solar', 'measurement' => 'Forecast' },
      'sensors' => { 'inverter_power_forecast' => { 'source' => 'forecast', 'measurement' => 'Forecast' } },
    }.merge(extra)
  end

  # Shape as the importer stores it: bare names take their value from
  # `env_values`, inline entries carry it, `${…}` indirects through either.
  def tibber_service(**overrides)
    {
      'image' => 'ghcr.io/solectrus/tibber-collector:latest',
      'depends_on' => { 'influxdb' => { 'condition' => 'service_healthy' } },
      'env_values' => { 'INFLUX_MEASUREMENT_TIBBER' => 'Tibber', 'TIBBER_TOKEN' => 'tibber-api-token-xyz',
                        'TIBBER_INTERVAL' => '3600' },
      'environment' => ['TZ', 'INFLUX_BUCKET', 'INFLUX_HOST=influxdb',
                        'INFLUX_MEASUREMENT=${INFLUX_MEASUREMENT_TIBBER}', 'INFLUX_ORG',
                        'INFLUX_TOKEN=${INFLUX_TOKEN}', 'TIBBER_INTERVAL', 'TIBBER_TOKEN'],
      'restart' => 'unless-stopped',
    }.merge(overrides)
  end

  def charger_service(**overrides)
    {
      'image' => 'ghcr.io/solectrus/senec-charger:latest',
      'env_values' => { 'CHARGER_DRY_RUN' => 'false', 'CHARGER_FORECAST_THRESHOLD' => '20',
                        'CHARGER_INTERVAL' => '3600', 'CHARGER_PRICE_MAX' => '70',
                        'CHARGER_PRICE_TIME_RANGE' => '4' },
      'environment' => ['TZ', 'INFLUX_HOST=influxdb', 'INFLUX_MEASUREMENT_PRICES=Tibber',
                        'CHARGER_DRY_RUN', 'CHARGER_FORECAST_THRESHOLD', 'CHARGER_INTERVAL',
                        'CHARGER_PRICE_MAX', 'CHARGER_PRICE_TIME_RANGE', 'SENEC_HOST', 'SENEC_SCHEMA'],
      'restart' => 'unless-stopped',
    }.merge(overrides)
  end

  context 'with an unmanaged tibber-collector' do
    let(:data) { base_data('_unmanaged' => { 'services' => { 'tibber-collector' => tibber_service } }) }

    it 'promotes it into a managed tibber section, resolving the indirect measurement' do
      up
      expect(data['tibber']).to eq(
        'token' => 'tibber-api-token-xyz',
        'measurement' => 'Tibber',
        'image' => 'ghcr.io/solectrus/tibber-collector:latest',
      )
    end

    it 'removes the passthrough and drops the emptied _unmanaged key' do
      up
      expect(data).not_to have_key('_unmanaged')
    end

    it 'exports a managed tibber-collector afterwards' do
      up
      expect(Export::Services::TibberCollector.enabled?(Configuration.from_data(data))).to be(true)
    end

    it 'leaves exactly one tibber-collector in the exported compose' do
      up
      yaml = Export::Compose.new(Configuration.from_data(data)).to_yaml
      expect(yaml.scan(/^ {2}tibber-collector:/).size).to eq(1)
    end
  end

  context 'with an unmanaged tibber-collector and senec-charger' do
    let(:data) do
      base_data('_unmanaged' => {
                  'services' => { 'senec-charger' => charger_service, 'tibber-collector' => tibber_service },
                })
    end

    it 'promotes the charger tuning into a managed senec_charger section' do
      up
      expect(data['senec_charger']).to eq(
        'interval' => '3600',
        'price_max' => '70',
        'price_time_range' => '4',
        'forecast_threshold' => '20',
        'dry_run' => false,
        'image' => 'ghcr.io/solectrus/senec-charger:latest',
      )
    end

    it 'promotes both services and leaves no passthrough behind' do
      up
      expect(data).not_to have_key('_unmanaged')
    end

    it 'exports both as managed services' do
      up
      config = Configuration.from_data(data)
      expect(Export::Services::SenecCharger.enabled?(config)).to be(true)
    end
  end

  context 'when the charger has no tibber-collector to read prices from' do
    let(:data) { base_data('_unmanaged' => { 'services' => { 'senec-charger' => charger_service } }) }

    it 'keeps the charger as passthrough rather than deleting a running service' do
      up
      expect(data.dig('_unmanaged', 'services')).to have_key('senec-charger')
    end

    it 'creates no half-configured senec_charger section' do
      up
      expect(data).not_to have_key('senec_charger')
    end
  end

  context 'when the charger has no forecast collector to read' do
    let(:data) do
      base_data('_unmanaged' => {
                  'services' => { 'senec-charger' => charger_service, 'tibber-collector' => tibber_service },
                }).except('forecast', 'sensors')
    end

    it 'promotes tibber but keeps the charger as passthrough' do
      up
      expect(data['tibber']).to be_present
      expect(data.dig('_unmanaged', 'services').keys).to eq(['senec-charger'])
    end
  end

  context 'when the tibber token cannot be resolved from the stored environment' do
    # Seen in the wild: a bare TIBBER_TOKEN with no env_values and no orphan
    # .env line — nothing to promote it with.
    let(:data) do
      base_data('_unmanaged' => {
                  'services' => { 'tibber-collector' => tibber_service.except('env_values') },
                })
    end

    it 'leaves the passthrough untouched' do
      up
      expect(data.dig('_unmanaged', 'services')).to have_key('tibber-collector')
      expect(data).not_to have_key('tibber')
    end
  end

  context 'when the token lives in an orphan _unmanaged env var' do
    let(:data) do
      base_data('_unmanaged' => {
                  'env_vars' => { 'TIBBER_TOKEN' => 'from-orphan', 'INFLUX_MEASUREMENT_TIBBER' => 'Tibber' },
                  'services' => { 'tibber-collector' => tibber_service.except('env_values') },
                })
    end

    it 'resolves it and promotes the service' do
      up
      expect(data['tibber']).to include('token' => 'from-orphan', 'measurement' => 'Tibber')
    end

    it 'keeps the orphan env vars, which are not this migration to clean up' do
      up
      expect(data.dig('_unmanaged', 'env_vars')).to include('TIBBER_TOKEN' => 'from-orphan')
    end
  end

  # In dashboard_only the tibber-collector keeps running (it only fetches a
  # public API, like the forecast-collector), while the charger needs the local
  # battery and does not.
  context 'when in dashboard_only mode' do
    let(:data) do
      base_data('_unmanaged' => {
                  'services' => { 'senec-charger' => charger_service, 'tibber-collector' => tibber_service },
                }).merge('deployment' => { 'mode' => 'dashboard_only' })
    end

    it 'promotes the tibber-collector, which still runs there' do
      up
      expect(data['tibber']).to include('token' => 'tibber-api-token-xyz')
    end

    it 'keeps the charger as passthrough rather than deleting a running service' do
      up
      expect(data.dig('_unmanaged', 'services').keys).to eq(['senec-charger'])
      expect(data).not_to have_key('senec_charger')
    end
  end

  context 'with a pinned develop channel' do
    let(:data) do
      base_data('_unmanaged' => {
                  'services' => {
                    'tibber-collector' => tibber_service('image' => 'ghcr.io/solectrus/tibber-collector:develop'),
                  },
                })
    end

    it 'carries the channel over instead of silently moving to the default' do
      up
      yaml = Export::Compose.new(Configuration.from_data(data)).to_yaml
      expect(yaml).to include('ghcr.io/solectrus/tibber-collector:develop')
    end
  end

  context 'with unrelated unmanaged services' do
    let(:data) do
      base_data('_unmanaged' => {
                  'services' => {
                    'dozzle' => { 'image' => 'amir20/dozzle:latest' },
                    'tibber-collector' => tibber_service,
                  },
                })
    end

    it 'promotes tibber and preserves the rest of the passthrough' do
      up
      expect(data.dig('_unmanaged', 'services').keys).to eq(['dozzle'])
    end
  end

  context 'without any _unmanaged key' do
    let(:data) { base_data }

    it 'leaves the data untouched' do
      expect(up).to eq(base_data)
    end
  end

  it 'is registered as version 4' do
    expect(described_class.version).to eq(4)
  end
end
