RSpec.describe Surveys::Sensor::Survey do
  describe '#call' do
    subject(:result) { described_class.new(sensor_name: 'custom_power_03').call }

    it 'returns nil for an unknown sensor' do
      expect(described_class.new(sensor_name: 'no_such_sensor').call).to be_nil
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

    it 'clears invisible values so filters of an abandoned source do not leak into config' do
      expect(result['clearInvisibleValues']).to eq('onHidden')
    end
  end
end
