RSpec.describe Surveys::MqttTopic::Survey do
  describe '#call' do
    subject(:result) { described_class.new.call }

    # `html` elements carry no value, so they are no part of the mapping schema.
    let(:all_field_names) do
      result['pages'].flat_map { |p| p['elements'].reject { |e| e['type'] == 'html' }.pluck('name') }
    end

    def page(name) = result['pages'].find { |p| p['name'] == name }
    def elements_of(name) = page(name)['elements'].index_by { |e| e['name'] }
    def kind_choice(value) = elements_of('p_kind')['kind']['choices'].find { |c| c['value'] == value }

    # Derived rather than copied, so a field added to the mapping schema
    # without a question in this survey fails here instead of silently
    # reaching the export with nothing to fill it.
    it 'covers the full mqtt-collector mapping schema plus the UI-only selectors' do
      # `kind` and `extraction_method` are stripped on save by MQTT_TOPIC_FIELDS.
      expect(all_field_names).to match_array(Configuration::MQTT_TOPIC_FIELDS + %w[kind extraction_method])
    end

    it 'requires only what every mapping needs, whatever its kind' do
      always_required = result['pages'].flat_map { |p| p['elements'] }
                                       .select { |e| e['isRequired'] && !e.key?('visibleIf') }
                                       .pluck('name')
      expect(always_required).to match_array(%w[kind type])
    end

    it 'clears invisible values so unused extraction fields do not leak into config' do
      expect(result['clearInvisibleValues']).to eq('onHidden')
    end

    # Everything that describes a topic hides for a calculated mapping, which
    # has none. mqtt-collector refuses JSON extraction on such a mapping.
    it 'gates topic and extraction on the kind' do
      expect(elements_of('p_topic')['topic']['visibleIf']).to eq("{kind} = 'topic'")
      expect(elements_of('p_extraction_method')['extraction_method']['visibleIf']).to eq("{kind} = 'topic'")
      expect(elements_of('p_extraction_value')['json_key']['visibleIf'])
        .to eq("{kind} = 'topic' and {extraction_method} = 'json_key'")
    end

    it 'always shows the extraction-value page, it hosts the data type both kinds need' do
      expect(page('p_extraction_value')).not_to have_key('visibleIf')
    end

    # A mapping with a topic resolves {value} alone. The collector refuses to
    # start on any other reference here, so the form refuses it first.
    it 'restricts the payload formula to {value}' do
      validator = elements_of('p_extraction_value')['formula']['validators'].sole

      expect(validator['type']).to eq('regex')
      expect(validator['regex']).to eq('^[^{]*(\\{value\\}[^{]*)+$')
    end

    # The numeric gate sits on the inputs, not on the page: clearInvisibleValues
    # clears a question only when its own visibility flips, so a page-level
    # condition left a stale min/max/null_to_zero behind after a type change.
    it 'gates each filter input on a numeric data type instead of the page' do
      condition = "({type} = 'float' or {type} = 'integer')"

      expect(page('p_filters')).not_to have_key('visibleIf')
      expect(elements_of('p_filters').transform_values { |e| e['visibleIf'] }).to eq(
        'min' => condition,
        'max' => condition,
        'null_to_zero' => condition,
      )
    end

    describe 'name' do
      let(:elements) { elements_of('p_name') }

      it 'offers an optional name plus a maximum age that needs it' do
        expect(elements['name']).not_to have_key('isRequired')
        expect(elements['max_age']['visibleIf']).to eq('{name} notempty')
      end

      # Mirrors MAPPING_NAME_REGEX of the collector, which restricts a name to
      # what survives its formula parser unchanged.
      it 'accepts only the characters the collector allows' do
        validator = elements['name']['validators'].find { |v| v['type'] == 'regex' }
        expect(validator['regex']).to eq('^[a-z_][a-z0-9_]*$')
      end

      it 'refuses the reserved name of the payload placeholder' do
        validator = elements['name']['validators'].find { |v| v['type'] == 'expression' }
        expect(validator['expression']).to include("{name} <> 'value'")
      end
    end

    describe 'write behavior' do
      let(:elements) { elements_of('p_write') }

      it 'gates each input on what the collector requires for it' do
        expect(page('p_write')).not_to have_key('visibleIf')
        expect(elements['aggregate_interval']['visibleIf'])
          .to eq("({type} = 'float' or {type} = 'integer') and {skip_write} <> true")
        expect(elements['dedup']['visibleIf']).to eq('{skip_write} <> true')
        expect(elements['heartbeat_interval']['visibleIf']).to eq('{dedup} = true and {skip_write} <> true')
      end

      # A mapping that is never written has nothing to throttle, and the
      # collector refuses the combination instead of ignoring it.
      it 'offers keeping a value in memory only, once it has a name' do
        expect(elements['skip_write']['visibleIf']).to eq('{name} notempty')
      end

      it 'leaves every write option optional' do
        expect(elements.values.pluck('isRequired').compact).to be_empty
      end

      it 'refuses a heartbeat that would make deduplication pointless' do
        validator = elements['heartbeat_interval']['validators'].sole

        expect(validator['type']).to eq('expression')
        expect(validator['expression']).to eq(
          '{aggregate_interval} empty or ' \
          'iif({heartbeat_interval} empty, 60, {heartbeat_interval}) > {aggregate_interval}',
        )
      end
    end

    # A mapping without a topic calculates its value from mappings that carry a
    # MAPPING_X_NAME. Without a single name there is nothing to calculate from.
    describe 'the calculated kind, with no name anywhere' do
      it 'offers the choice but disables it' do
        expect(kind_choice('computed')['enableIf']).to eq('false')
      end

      it 'omits the formula field, there is nothing it could reference' do
        expect(all_field_names).not_to include('computed_formula')
      end
    end

    describe 'the calculated kind, with a named mapping' do
      before do
        with_config_yaml(
          'sensors' => {
            'house_power' => { 'source' => 'mqtt', 'mqtt_topic' => 'h/p', 'mqtt_name' => 'house_power' },
          },
        )
      end

      it 'enables the choice' do
        expect(kind_choice('computed')).not_to have_key('enableIf')
      end

      it 'asks for the formula in its own field, apart from the payload formula' do
        formula = elements_of('p_extraction_value')['computed_formula']

        expect(formula['visibleIf']).to eq("{kind} = 'computed'")
        expect(formula['isRequired']).to be true
      end

      # Building the pattern from the known names catches a typo in the form.
      # Otherwise the collector refuses to start, and only its own log says why.
      it 'accepts only references the collector can resolve' do
        validator = elements_of('p_extraction_value')['computed_formula']['validators'].sole

        expect(validator['type']).to eq('regex')
        expect(validator['regex']).to eq('^[^{]*(\\{(house_power)\\}[^{]*)+$')
      end

      it 'lists the available names' do
        expect(elements_of('p_extraction_value')['reference_hint']['html']['default']).to include('house_power')
      end
    end
  end

  # A name must be unique, and a formula must not reference a mapping that
  # reads this one, so the survey needs to know which entry is being edited.
  describe 'editing an existing entry' do
    before do
      with_config_yaml(
        'mqtt' => {
          'mappings' => [
            { 'topic' => 'a/b', 'name' => 'washer', 'measurement' => 'm', 'field' => 'a' },
            { 'name' => 'rest', 'formula' => '{washer} * 2', 'measurement' => 'm', 'field' => 'b' },
            { 'topic' => 'c/d', 'name' => 'dryer', 'measurement' => 'm', 'field' => 'c' },
          ],
        },
      )
    end

    def elements_for(index, page)
      described_class.new(index:).call['pages'].find { |p| p['name'] == page }['elements'].index_by { |e| e['name'] }
    end

    it 'leaves the entry out of its own uniqueness check' do
      expression = elements_for(0, 'p_name')['name']['validators'].find { |v| v['type'] == 'expression' }['expression']

      expect(expression).to include("{name} <> 'rest'").and include("{name} <> 'dryer'")
      expect(expression).not_to include("{name} <> 'washer'")
    end

    it 'makes the name mandatory while a formula reads it' do
      expect(elements_for(0, 'p_name')['name']['isRequired']).to be true
      expect(elements_for(1, 'p_name')['name']).not_to have_key('isRequired')
    end

    it 'names the entries that read it' do
      expect(elements_for(0, 'p_name')['name']['description']['default']).to include('rest')
    end

    # `rest` reads `washer`, so offering it back to `washer` would let the user
    # close a cycle, which mqtt-collector refuses at startup.
    it 'hides a reference that would point back at the entry' do
      hint = elements_for(0, 'p_extraction_value')['reference_hint']['html']['default']

      expect(hint).to include('dryer')
      expect(hint).not_to include('rest')
    end

    it 'offers every other name to an entry that nothing reads' do
      hint = elements_for(2, 'p_extraction_value')['reference_hint']['html']['default']

      expect(hint).to include('washer').and include('rest')
    end
  end
end
