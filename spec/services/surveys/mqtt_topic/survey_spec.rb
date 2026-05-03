RSpec.describe Surveys::MqttTopic::Survey do
  describe '#call' do
    subject(:result) { described_class.new.call }

    let(:all_field_names) { result['pages'].flat_map { |p| p['elements'].pluck('name') } }

    it 'covers the full mqtt-collector mapping schema plus the extraction selector' do
      # Mirrors Export::Services::MqttCollector::COLLECTORS_ONLY_MAPPING_KEYS,
      # plus the virtual `extraction_method` selector (stripped on save by MQTT_TOPIC_FIELDS).
      expect(all_field_names).to match_array(
        %w[topic measurement field type extraction_method json_key json_path json_formula formula min max null_to_zero],
      )
    end

    it 'requires the four core fields plus the extraction method' do
      always_required = result['pages'].flat_map { |p| p['elements'] }
                                       .select { |e| e['isRequired'] && !e.key?('visibleIf') }
                                       .pluck('name')
      expect(always_required).to match_array(%w[topic measurement field type extraction_method])
    end

    it 'always shows the extraction-value page (it now hosts the data type) so each conditional input gates itself' do
      value_page = result['pages'].find { |p| p['name'] == 'p_extraction_value' }
      expect(value_page).not_to have_key('visibleIf')
    end

    it 'shows each extraction-value input only for its matching method' do
      value_page = result['pages'].find { |p| p['name'] == 'p_extraction_value' }
      conditions = value_page['elements'].select { |e| e.key?('visibleIf') }.to_h { |e| [e['name'], e['visibleIf']] }
      expect(conditions).to eq(
        'json_key' => "{extraction_method} = 'json_key'",
        'json_path' => "{extraction_method} = 'json_path'",
        'json_formula' => "{extraction_method} = 'json_formula'",
        'formula' => "{extraction_method} = 'formula'",
      )
    end

    it 'clears invisible values so unused extraction fields do not leak into config' do
      expect(result['clearInvisibleValues']).to eq('onHidden')
    end

    it 'hides the filters page for non-numeric data types' do
      filters_page = result['pages'].find { |p| p['name'] == 'p_filters' }
      expect(filters_page['visibleIf']).to include("{type} = 'float'", "{type} = 'integer'")
    end
  end
end
