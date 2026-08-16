RSpec.describe Surveys::Sensor::Survey do
  describe '#call' do
    subject(:result) { described_class.new(sensor_name: 'custom_power_03').call }

    it 'returns nil for an unknown sensor' do
      expect(described_class.new(sensor_name: 'no_such_sensor').call).to be_nil
    end

    def computed_choice(survey)
      kind = survey['pages'].find { |p| p['name'] == 'p_mqtt_kind' }['elements'].sole
      kind['choices'].find { |c| c['value'] == 'computed' }
    end

    describe 'MQTT filter page' do
      let(:filter_page) { result['pages'].find { |p| p['name'] == 'p_mqtt_filter' } }
      let(:condition) { "{source} = 'mqtt' and ({mqtt_payload_type} = 'float' or {mqtt_payload_type} = 'integer')" }

      it 'offers the numeric filters plus the NULL-to-zero switch' do
        expect(filter_page['elements'].pluck('name')).to eq(%w[mqtt_min mqtt_max mqtt_null_to_zero])
      end

      # The gate sits on the inputs, not on the page: clearInvisibleValues
      # clears a question only when its own visibility flips, so a page-level
      # condition left a stale MAPPING_N_NULL_TO_ZERO=true in the export after
      # the payload type changed from float to string. SurveyJS hides a page
      # whose questions are all invisible on its own.
      it 'gates each input on an MQTT sensor with a numeric payload' do
        expect(filter_page).not_to have_key('visibleIf')
        expect(filter_page['elements'].pluck('visibleIf')).to all(eq(condition))
      end

      it 'defaults the NULL-to-zero switch to off' do
        element = find_survey_element(result, 'mqtt_null_to_zero')
        expect(element).to include('type' => 'boolean', 'defaultValue' => false)
      end
    end

    describe 'MQTT write-behavior page' do
      # No released mqtt-collector reads these variables, so the page exists
      # for the development channel alone.
      before { with_config_yaml('mqtt' => { 'image' => 'ghcr.io/solectrus/mqtt-collector:develop' }) }

      let(:write_page) { result['pages'].find { |p| p['name'] == 'p_mqtt_write' } }
      let(:elements) { write_page['elements'].index_by { |e| e['name'] } }

      it 'offers the averaging interval plus deduplication with its heartbeat' do
        expect(write_page['elements'].pluck('name')).to eq(
          %w[mqtt_aggregate_interval mqtt_dedup mqtt_heartbeat_interval],
        )
      end

      it 'disappears while the collector runs on the stable channel' do
        with_config_yaml('mqtt' => { 'image' => 'ghcr.io/solectrus/mqtt-collector:latest' })

        expect(write_page).to be_nil
        expect(find_survey_element(result, 'mqtt_dedup')).to be_nil
      end

      # Every gate carries the MQTT source, so switching a sensor to Shelly or
      # external clears the write options along with the rest of the MQTT page.
      it 'gates each input on an MQTT sensor and on what the collector requires' do
        expect(write_page).not_to have_key('visibleIf')
        expect(elements['mqtt_aggregate_interval']['visibleIf']).to eq(
          "{source} = 'mqtt' and ({mqtt_payload_type} = 'float' or {mqtt_payload_type} = 'integer')",
        )
        expect(elements['mqtt_dedup']['visibleIf']).to eq("{source} = 'mqtt'")
        expect(elements['mqtt_heartbeat_interval']['visibleIf']).to eq("{source} = 'mqtt' and {mqtt_dedup} = true")
      end

      it 'defaults deduplication to off' do
        expect(elements['mqtt_dedup']).to include('type' => 'boolean', 'defaultValue' => false)
      end
    end

    describe 'MQTT name page' do
      let(:elements) { result['pages'].find { |p| p['name'] == 'p_mqtt_name' }['elements'].index_by { |e| e['name'] } }

      it 'offers an optional name plus a maximum age that needs it' do
        expect(elements['mqtt_name']['visibleIf']).to eq("{source} = 'mqtt'")
        expect(elements['mqtt_name']).not_to have_key('isRequired')
        expect(elements['mqtt_max_age']['visibleIf']).to eq("{source} = 'mqtt' and {mqtt_name} notempty")
      end
    end

    # A sensor is normally fed by a topic. Calculating it from other mappings
    # covers a value no device sends, e.g. a base load from the house power.
    describe 'the calculated kind, with no name anywhere' do
      it 'disables the choice' do
        expect(computed_choice(result)['enableIf']).to eq('false')
      end
    end

    describe 'the calculated kind, with a named mapping to read' do
      before do
        with_config_yaml(
          'mqtt' => { 'mappings' => [{ 'topic' => 'a/b', 'name' => 'washer', 'measurement' => 'm',
                                       'field' => 'a' }] },
        )
      end

      it 'enables the choice' do
        expect(computed_choice(result)).not_to have_key('enableIf')
      end

      # A calculated sensor has no payload, so the collector refuses a topic
      # and every JSON extraction on it.
      it 'hides topic and extraction for it' do
        topic = result['pages'].find { |p| p['name'] == 'p_mqtt' }['elements'].sole
        extraction = result['pages'].find { |p| p['name'] == 'p_mqtt_extraction' }['elements'].sole

        expect(topic['visibleIf']).to eq("{source} = 'mqtt' and {mqtt_kind} = 'topic'")
        expect(extraction['visibleIf']).to eq("{source} = 'mqtt' and {mqtt_kind} = 'topic'")
      end

      it 'asks for the formula in its own field' do
        formula = find_survey_element(result, 'mqtt_computed_formula')

        expect(formula['visibleIf']).to eq("{source} = 'mqtt' and {mqtt_kind} = 'computed'")
        expect(formula['validators'].sole['regex']).to eq('^[^{]*(\\{(washer)\\}[^{]*)+$')
      end
    end

    it 'clears invisible values so filters of an abandoned source do not leak into config' do
      expect(result['clearInvisibleValues']).to eq('onHidden')
    end
  end
end
