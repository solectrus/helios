RSpec.describe SensorRow::Component, type: :component do
  subject(:rendered) do
    render_inline(described_class.new(sensor_name:, configuration: Configuration.current, reading:))
  end

  let(:sensor_name) { 'inverter_power' }
  let(:reading) { nil }

  before do
    Configuration.current.update_sensor('inverter_power', { 'source' => 'senec' })
  end

  it 'shows the expected unit while no value has arrived' do
    expect(rendered).to have_text('W')
  end

  context 'with a numeric reading' do
    let(:reading) { Reading.new(value: 1234.56, time: Time.zone.now) }

    it 'renders it with one decimal' do
      expect(rendered).to have_text('1234.6')
    end
  end

  context 'with a boolean reading' do
    let(:sensor_name) { 'car_battery_soc' }
    let(:reading) { Reading.new(value: 'true', time: Time.zone.now) }

    it 'renders a label instead of the raw value' do
      Configuration.current.update_sensor(sensor_name, { 'source' => 'mqtt' })

      expect(rendered).to have_no_text('true')
    end
  end

  # house_power is what the dashboard subtracts the excluded consumers from,
  # so the row names them.
  describe 'the house-power exclusion hint' do
    let(:sensor_name) { 'house_power' }

    before do
      Configuration.current.update_sensor('house_power', { 'source' => 'senec' })
      Configuration.current.update_sensor('custom_power_01', {
                                            'source' => 'mqtt', 'measurement' => 'Oven',
                                            'field' => 'power', 'exclude_from_house_power' => true
                                          })
    end

    it 'names the excluded sensors in the tooltip' do
      expect(rendered.css('[data-tip]').first['data-tip']).to include('CUSTOM_POWER_01')
    end
  end
end
