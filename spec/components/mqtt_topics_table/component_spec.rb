RSpec.describe MqttTopicsTable::Component, type: :component do
  subject(:rendered) { render_inline(component) }

  let(:component) { described_class.new(topics:, graph:, readings:) }
  let(:graph) { Mqtt::MappingGraph.new(Configuration.current) }
  let(:readings) { {} }
  let(:topics) { [topic] }
  let(:topic) do
    { 'topic' => 'home/power', 'measurement' => 'MQTT', 'field' => 'power', 'type' => 'float' }
  end

  it 'shows the topic as the headline' do
    expect(rendered).to have_text('home/power')
  end

  # Each option shows up as a short badge; the tooltip carries the meaning.
  describe 'badges' do
    {
      'the JSON key the value is taken from' =>
        [{ 'json_key' => 'total_power' }, 'total_power'],
      'a minimum and a maximum as one range' =>
        [{ 'min' => '0', 'max' => '100' }, I18n.t('datasources.mqtt_topics.filters.range', min: '0', max: '100')],
      'the lower bound alone' =>
        [{ 'min' => '0' }, I18n.t('datasources.mqtt_topics.filters.min', min: '0')],
      'the upper bound alone' =>
        [{ 'max' => '100' }, I18n.t('datasources.mqtt_topics.filters.max', max: '100')],
      'the NULL-to-zero switch' =>
        [{ 'null_to_zero' => true }, I18n.t('datasources.mqtt_topics.filters.null_to_zero')],
    }.each do |what, (option, text)|
      it "shows #{what}" do
        expect(render_inline(described_class.new(topics: [topic.merge(option)], graph:, readings:)))
          .to have_text(text)
      end
    end
  end

  describe 'live values' do
    let(:readings) { { '0' => Reading.new(value: 42.5, time: Time.zone.now) } }

    it 'renders the reading in the value cell' do
      expect(rendered).to have_text('42.50')
      expect(rendered.css('#mqtt-topic-value-0')).to be_present
    end

    it 'switches the list to polling' do
      expect(rendered.css('[data-controller="sensors-polling"]')).to be_present
    end
  end

  # A mapping the collector has not written yet keeps its cell, so the row
  # does not change height once the value arrives.
  context 'when a topic has no reading of its own' do
    let(:readings) { { '1' => Reading.new(value: 1) } }

    it 'renders the placeholder' do
      expect(rendered).to have_text(Reading::EMPTY_DISPLAY)
    end
  end

  context 'without any readings' do
    it 'skips the polling controller entirely' do
      expect(rendered.css('[data-controller="sensors-polling"]')).to be_empty
    end
  end

  context 'without any topics' do
    let(:topics) { [] }

    it 'renders the empty state' do
      expect(rendered).to have_text(I18n.t('datasources.mqtt_topics.index.empty'))
    end
  end
end
