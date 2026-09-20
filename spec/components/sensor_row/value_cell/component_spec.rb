RSpec.describe SensorRow::ValueCell::Component, type: :component do
  subject(:rendered) { render_inline(described_class.new(sensor_row:)) }

  let(:sensor_row) do
    SensorRow::Component.new(sensor_name: 'inverter_power', configuration: Configuration.current, reading:)
  end
  let(:reading) { Reading.new(value: 1234.56, time: Time.zone.now) }

  before { Configuration.current.update_sensor('inverter_power', { 'source' => 'senec' }) }

  it 'shows the value' do
    expect(rendered).to have_text('1234.6')
  end

  # A phone has no hover, and the age of the reading stands nowhere else on the
  # screen. It therefore hangs on a trigger a finger and the Tab key reach, not
  # on a daisyUI tooltip, which a pointer alone can open.
  describe 'the age of the reading' do
    it 'hangs on a focusable trigger' do
      trigger = rendered.css('.hint button').first

      expect(trigger).to be_present
      expect(trigger).to have_text('1234.6')
      expect(trigger.attr('tabindex')).to be_nil
    end

    it 'is written into the bubble by the relative-time controller' do
      bubble = rendered.css('.hint .dropdown-content [data-controller="relative-time"]').first

      expect(bubble.attr('data-relative-time-datetime-value')).to eq(reading.time.iso8601)
      expect(bubble.attr('data-relative-time-target-value')).to eq('text')
    end

    it 'does not hide in a tooltip' do
      expect(rendered.css('.tooltip')).to be_empty
    end
  end

  context 'without a reading' do
    let(:reading) { nil }

    it 'shows the expected unit instead of an empty hint' do
      expect(rendered).to have_text('W')
      expect(rendered.css('.hint')).to be_empty
    end
  end
end
