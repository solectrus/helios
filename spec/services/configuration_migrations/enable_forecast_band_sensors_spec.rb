RSpec.describe ConfigurationMigrations::EnableForecastBandSensors do
  subject(:up) { described_class.new.up(data) }

  let(:forecast) do
    { 'forecast' => 'pvnode', 'forecast_pvnode_site_id' => 'site-1', 'forecast_pvnode_paid' => 'nowcast' }
  end
  let(:sensors) { { 'inverter_power_forecast' => { 'source' => 'forecast' } } }
  let(:data) { { 'forecast' => forecast, 'sensors' => sensors } }

  let(:band_sensors) do
    {
      'inverter_power_forecast_min' => { 'source' => 'forecast' },
      'inverter_power_forecast_max' => { 'source' => 'forecast' },
    }
  end

  context 'with pvnode, a site ID and the Plus plan' do
    it 'enables both sensors of the band' do
      expect(up['sensors']).to eq(sensors.merge(band_sensors))
    end
  end

  context 'with a sensor of the band already present' do
    let(:sensors) do
      {
        'inverter_power_forecast' => { 'source' => 'forecast' },
        'inverter_power_forecast_min' => { 'source' => 'external', 'measurement' => 'band', 'field' => 'low' },
      }
    end

    it 'keeps that entry and adds the missing one' do
      expect(up['sensors']).to eq(
        sensors.merge('inverter_power_forecast_max' => { 'source' => 'forecast' }),
      )
    end
  end

  shared_examples 'no band' do
    it 'enables nothing' do
      expect(up['sensors']).to eq(sensors)
    end
  end

  context 'with the Free plan' do
    let(:forecast) { super().merge('forecast_pvnode_paid' => 'false') }

    it_behaves_like 'no band'
  end

  context 'with the Light plan' do
    let(:forecast) { super().merge('forecast_pvnode_paid' => 'true') }

    it_behaves_like 'no band'
  end

  context 'without a site ID' do
    let(:forecast) { super().except('forecast_pvnode_site_id') }

    it_behaves_like 'no band'
  end

  context 'with another forecast provider' do
    let(:forecast) { super().merge('forecast' => 'forecast.solar') }

    it_behaves_like 'no band'
  end

  context 'with the PV forecast read from another source' do
    let(:sensors) do
      { 'inverter_power_forecast' => { 'source' => 'external', 'measurement' => 'pv', 'field' => 'forecast' } }
    end

    it_behaves_like 'no band'
  end

  context 'without the PV forecast sensor' do
    let(:sensors) { { 'inverter_power' => { 'source' => 'senec' } } }

    it_behaves_like 'no band'
  end

  context 'without a sensors section' do
    let(:data) { { 'forecast' => forecast } }

    it 'leaves the data as it is' do
      expect(up).to eq('forecast' => forecast)
    end
  end
end
