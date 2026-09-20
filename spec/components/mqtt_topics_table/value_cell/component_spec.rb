RSpec.describe MqttTopicsTable::ValueCell::Component, type: :component do
  subject(:rendered) { render_inline(described_class.new(index: 0, reading:)) }

  let(:reading) { Reading.new(value: 42.5, time: Time.zone.now) }

  it 'shows the value' do
    expect(rendered).to have_text('42.5')
  end

  # See SensorRow::ValueCell: the age of the reading has to open without a
  # pointer as well.
  describe 'the age of the reading' do
    it 'hangs on a focusable trigger' do
      trigger = rendered.css('.hint button').first

      expect(trigger).to be_present
      expect(trigger).to have_text('42.5')
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

    it 'shows a placeholder without a hint' do
      expect(rendered).to have_text(Reading::EMPTY_DISPLAY)
      expect(rendered.css('.hint')).to be_empty
    end
  end
end
