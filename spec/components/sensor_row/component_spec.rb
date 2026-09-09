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

    it 'names the excluded sensors by their label, not by their internal name' do
      items = rendered.css('.tooltip-content li').map(&:text)

      expect(items).to eq([I18n.t('sensors.custom_power_01')])
      expect(rendered.to_html).not_to include('CUSTOM_POWER_01')
    end

    it 'lists several excluded sensors as their own items' do
      Configuration.current.update_sensor('custom_power_02', {
                                            'source' => 'mqtt', 'measurement' => 'Fridge',
                                            'field' => 'power', 'exclude_from_house_power' => true
                                          })

      expect(rendered.css('.tooltip-content li').size).to eq(2)
    end

    it 'prefers the name the owner gave a custom sensor' do
      Configuration.current.update_sensor('custom_power_01', {
                                            'source' => 'mqtt', 'measurement' => 'Oven',
                                            'field' => 'power', 'exclude_from_house_power' => true,
                                            'name' => 'Backofen'
                                          })

      expect(rendered.css('.tooltip-content li').map(&:text)).to eq(['Backofen'])
    end
  end

  # An external source only reaches the house-power calculation when it writes
  # to Ingest, and nothing but this hint says so on the sensor list.
  describe 'the Ingest address hint' do
    let(:sensor_name) { 'house_power' }

    before do
      Configuration.current.update('system', { 'app_host' => 'solectrus.fritz.box' })
      Configuration.current.update_sensor('house_power', {
                                            'source' => 'external', 'measurement' => 'house', 'field' => 'power'
                                          })
    end

    context 'with a balcony power plant that runs Ingest' do
      before do
        Configuration.current.update_sensor('inverter_power_2', {
                                              'source' => 'shelly', 'is_balcony' => true,
                                              'shelly_host' => 'shelly.local',
                                              'measurement' => 'balcony', 'field' => 'power'
                                            })
      end

      it 'names the address next to the source badge' do
        expect(rendered.css('.tooltip-content').text).to include('http://solectrus.fritz.box:4567')
      end

      it 'names the port alone while no address is configured' do
        Configuration.current.update('system', { 'app_host' => '' })

        text = rendered.css('.tooltip-content').text
        expect(text).to include(Export::IngestEndpoint::PORT.to_s)
        expect(text).not_to include('http')
      end

      it 'leads with a bold marker' do
        expect(rendered.css('.tooltip-content strong').first.text).to eq(I18n.t('sensors.ingest_endpoint_hint_lead'))
      end

      # Every input of the house-power formula counts, not just the balcony one:
      # a single value missing from Ingest stops the calculation entirely.
      it 'sits on every Ingest input that comes from an external source' do
        # inverter_power_2 stays the Shelly balcony sensor: turning it external
        # too would drop the flag and switch Ingest off mid-loop.
        without_hint =
          (SensorRegistry::INGEST_SENSORS - %w[inverter_power_2]).reject do |name|
            Configuration.current.update_sensor(
              name, { 'source' => 'external', 'measurement' => name, 'field' => 'power' }
            )
            row = described_class.new(sensor_name: name, configuration: Configuration.current, reading: nil)
            render_inline(row).css('.tooltip-content').any?
          end

        expect(without_hint).to be_empty
      end
    end

    it 'stays away while no Ingest runs' do
      expect(rendered.css('.tooltip-content')).to be_empty
    end

    it 'stays away on a sensor Ingest does not consume' do
      Configuration.current.update_sensor('inverter_power_2', {
                                            'source' => 'shelly', 'is_balcony' => true,
                                            'shelly_host' => 'shelly.local',
                                            'measurement' => 'balcony', 'field' => 'power'
                                          })
      Configuration.current.update_sensor('outdoor_temp', {
                                            'source' => 'external', 'measurement' => 'outdoor', 'field' => 'temp'
                                          })

      rendered = render_inline(
        described_class.new(sensor_name: 'outdoor_temp', configuration: Configuration.current, reading: nil),
      )
      expect(rendered.css('.tooltip-content')).to be_empty
    end
  end
end
