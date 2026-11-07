RSpec.describe Export::Services::PublicDataCollector do
  def config_with(channel: 'develop', system: { 'country' => 'DE' }, mode: 'full',
                  sensors: { 'car_odometer' => { 'source' => 'mqtt' } }, image: nil)
    Configuration.from_data(
      'deployment' => { 'mode' => mode },
      'system' => system,
      'dashboard' => { 'image' => "ghcr.io/solectrus/solectrus:#{channel}" },
      'influxdb' => { 'org' => 'solectrus', 'bucket' => 'solectrus' },
      'sensors' => sensors,
      'public_data_collector' => { 'image' => image }.compact,
    )
  end

  describe '.enabled?' do
    it 'is enabled for a car on the develop channel of the dashboard' do
      expect(described_class.enabled?(config_with)).to be(true)
    end

    it 'is disabled on the stable channel' do
      expect(described_class.enabled?(config_with(channel: 'latest'))).to be(false)
    end

    it 'is disabled without a car' do
      config = config_with(sensors: { 'inverter_power' => { 'source' => 'mqtt' } })
      expect(described_class.enabled?(config)).to be(false)
    end

    it 'is disabled for a car without an odometer, which gives no mileage to compare' do
      config = config_with(sensors: { 'car_battery_soc' => { 'source' => 'mqtt' } })
      expect(described_class.enabled?(config)).to be(false)
    end

    # The dashboard gets no mileage from an entry without a source.
    it 'is disabled for an odometer without a mapping' do
      expect(described_class.enabled?(config_with(sensors: { 'car_odometer' => {} }))).to be(false)
    end

    it 'is enabled for the odometer of a further car' do
      config = config_with(sensors: { 'car_odometer_2' => { 'source' => 'mqtt' } })
      expect(described_class.enabled?(config)).to be(true)
    end

    it 'is enabled for the heat of a heat pump, to compare it with an oil or a gas heating' do
      config = config_with(sensors: { 'heatpump_heating_power' => { 'source' => 'mqtt' } })
      expect(described_class.enabled?(config)).to be(true)
    end

    it 'is disabled for a heat pump without the sensor of its heat' do
      config = config_with(sensors: { 'heatpump_power' => { 'source' => 'mqtt' } })
      expect(described_class.enabled?(config)).to be(false)
    end

    it 'is disabled outside the European Union, where the bulletin has no prices' do
      expect(described_class.enabled?(config_with(system: { 'country' => 'other' }))).to be(false)
    end

    # The dashboard shows the prices in euros alone.
    it 'is disabled for another currency' do
      expect(described_class.enabled?(config_with(system: { 'country' => 'PL', 'currency' => 'PLN' }))).to be(false)
      expect(described_class.enabled?(config_with(system: { 'country' => 'DE', 'currency' => 'eur' }))).to be(true)
    end

    it 'takes the country from the timezone while none is chosen' do
      expect(described_class.enabled?(config_with(system: {}))).to be(true)
    end

    it 'is disabled in collectors_only mode, where the dashboard host runs it' do
      expect(described_class.enabled?(config_with(mode: 'collectors_only'))).to be(false)
    end

    it 'stays enabled in dashboard_only mode' do
      expect(described_class.enabled?(config_with(mode: 'dashboard_only'))).to be(true)
    end
  end

  describe '#to_h' do
    it 'switches on the fuel prices and writes to influxdb directly' do
      service = described_class.new(config_with(system: { 'country' => 'AT' })).to_h

      expect(service[:environment]).to contain_exactly(
        'TZ', 'INFLUX_ORG', 'INFLUX_BUCKET',
        'INFLUX_HOST=influxdb', 'INFLUX_PORT=8086', 'INFLUX_SCHEMA=http',
        'INFLUX_TOKEN=${INFLUX_TOKEN_READWRITE}',
        'COUNTRY', 'ENABLE_FUEL=true'
      )
      expect(service[:depends_on]).to eq(influxdb: { condition: 'service_healthy' })
    end

    it 'switches on the gas price for the heat of a heat pump' do
      config = config_with(sensors: { 'heatpump_heating_power' => { 'source' => 'mqtt' } })

      expect(described_class.new(config).to_h[:environment]).to include('ENABLE_FUEL=true', 'ENABLE_GAS=true')
    end

    it 'defaults to the stable image' do
      expect(described_class.new(config_with).to_h[:image]).to eq('ghcr.io/solectrus/public-data-collector:latest')
    end

    it 'honors a chosen develop image channel' do
      config = config_with(image: 'ghcr.io/solectrus/public-data-collector:develop')
      expect(described_class.new(config).to_h[:image]).to eq('ghcr.io/solectrus/public-data-collector:develop')
    end
  end

  describe 'COUNTRY in .env' do
    def env_for(config) = Export::Env.new(config).to_s

    it 'carries the country while the service runs' do
      expect(env_for(config_with(system: { 'country' => 'AT' }))).to include('COUNTRY=AT')
    end

    it 'is left out while the service does not run' do
      expect(env_for(config_with(system: { 'country' => 'AT' }, channel: 'latest'))).not_to include('COUNTRY')
    end
  end
end
