RSpec.describe ConfigurationMigrations::DeriveFixedSourceMappings do
  subject(:up) { described_class.new.up(data) }

  def data_with(sensors, sections = { 'forecast' => {} })
    { 'sensors' => sensors }.merge(sections)
  end

  def forecast_sensor(measurement, field = 'watt')
    { 'inverter_power_forecast' => { 'source' => 'forecast', 'measurement' => measurement, 'field' => field }.compact }
  end

  # The name an earlier HELIOS handed the collector where the section named
  # none. The collector writes there today, so the name is written out.
  context 'with a forecast section that names no measurement' do
    let(:data) { data_with(forecast_sensor(nil)) }

    it 'writes the name the collector has been given' do
      expect(up['forecast']['measurement']).to eq('forecast')
    end
  end

  context 'with sensors carrying a copy of that name' do
    let(:data) { data_with(forecast_sensor('forecast')) }

    it 'keeps the collector where it writes' do
      expect(up['forecast']['measurement']).to eq('forecast')
    end

    it 'drops the copy, which now says what the source says' do
      expect(up['sensors']['inverter_power_forecast']).to eq('source' => 'forecast')
    end
  end

  # The import stored what the donated stack read, and an earlier HELIOS sent
  # the collector elsewhere. The two disagree, and the update moves neither.
  context 'with sensors reading somewhere else than the collector writes' do
    let(:data) { data_with(forecast_sensor('Forecast')) }

    it 'keeps the collector where it writes' do
      expect(up['forecast']['measurement']).to eq('forecast')
    end

    it 'keeps the mapping, which says where that sensor reads' do
      expect(up['sensors']['inverter_power_forecast']).to eq(
        'source' => 'forecast', 'measurement' => 'Forecast', 'field' => 'watt',
      )
    end
  end

  context 'with a name the section carries itself' do
    let(:data) { data_with(forecast_sensor('Prognose'), 'forecast' => { 'measurement' => 'Prognose' }) }

    it 'keeps that name' do
      expect(up['forecast']['measurement']).to eq('Prognose')
    end

    it 'drops the copy of it' do
      expect(up['sensors']['inverter_power_forecast']).to eq('source' => 'forecast')
    end
  end

  context 'with a field the sensor does not derive' do
    let(:data) { data_with(forecast_sensor('forecast', 'watt_clearsky')) }

    it 'keeps the mapping' do
      expect(up['sensors']['inverter_power_forecast']).to eq(
        'source' => 'forecast', 'measurement' => 'forecast', 'field' => 'watt_clearsky',
      )
    end
  end

  context 'with a mapping of the SENEC collector' do
    let(:data) do
      data_with({ 'inverter_power' => { 'source' => 'senec', 'measurement' => 'SENEC', 'field' => 'inverter_power' } },
                'senec' => { 'version' => '4' })
    end

    it 'writes no name out, because HELIOS has always agreed with that collector' do
      expect(up['senec']).to eq('version' => '4')
    end

    it 'drops the copy' do
      expect(up['sensors']['inverter_power']).to eq('source' => 'senec')
    end
  end

  context 'with a source that carries its measurement per sensor' do
    let(:data) { data_with('heatpump_power' => { 'source' => 'shelly', 'measurement' => 'heatpump' }) }

    it 'keeps the mapping' do
      expect(up['sensors']['heatpump_power']).to eq('source' => 'shelly', 'measurement' => 'heatpump')
    end
  end

  context 'with sensors of a source the configuration does not hold' do
    let(:data) { { 'sensors' => forecast_sensor('forecast') } }

    it 'writes no section of its own' do
      expect(up).not_to have_key('forecast')
    end
  end

  context 'without sensors' do
    let(:data) { { 'system' => { 'timezone' => 'Europe/Berlin' } } }

    it 'passes the data through' do
      expect(up).to eq(data)
    end
  end

  context 'with a sensor that holds no configuration' do
    let(:data) { data_with('inverter_power' => nil) }

    it 'passes the data through' do
      expect(up['sensors']).to eq('inverter_power' => nil)
    end
  end
end
