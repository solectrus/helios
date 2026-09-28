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

      it 'offers the numeric filters plus the NULL-to-zero switch' do
        expect(filter_page['elements'].pluck('name')).to eq(%w[mqtt_min mqtt_max mqtt_null_to_zero])
      end

      # The gate sits on the inputs, not on the page: clearInvisibleValues
      # clears a question only when its own visibility flips, and SurveyJS
      # hides a page whose questions are all invisible on its own.
      it 'gates each input on an MQTT sensor' do
        expect(filter_page).not_to have_key('visibleIf')
        expect(filter_page['elements'].pluck('visibleIf')).to all(eq("{source} = 'mqtt'"))
      end

      # A yes/no sensor has no numbers to filter, and the type is known while
      # the survey is built, so the inputs are left out instead of hidden.
      it 'drops the filters for a sensor that carries no number' do
        survey = described_class.new(sensor_name: 'wallbox_car_connected').call

        expect(survey['pages'].find { |p| p['name'] == 'p_mqtt_filter' }['elements']).to be_empty
      end

      it 'defaults the NULL-to-zero switch to off' do
        element = find_survey_element(result, 'mqtt_null_to_zero')
        expect(element).to include('type' => 'boolean', 'defaultValue' => false)
      end
    end

    describe 'MQTT write-behavior page' do
      let(:write_page) { result['pages'].find { |p| p['name'] == 'p_mqtt_write' } }
      let(:elements) { write_page['elements'].index_by { |e| e['name'] } }

      it 'offers the averaging interval plus deduplication with its heartbeat' do
        expect(write_page['elements'].pluck('name')).to eq(
          %w[mqtt_aggregate_interval mqtt_dedup mqtt_heartbeat_interval],
        )
      end

      # Every gate carries the MQTT source, so switching a sensor to Shelly or
      # external clears the write options along with the rest of the MQTT page.
      it 'gates each input on an MQTT sensor and on what the collector requires' do
        expect(write_page).not_to have_key('visibleIf')
        expect(elements['mqtt_aggregate_interval']['visibleIf']).to eq("{source} = 'mqtt'")
        expect(elements['mqtt_dedup']['visibleIf']).to eq("{source} = 'mqtt'")
        expect(elements['mqtt_heartbeat_interval']['visibleIf']).to eq("{source} = 'mqtt' and {mqtt_dedup} = true")
      end

      # Averaging needs numbers to average, so a yes/no sensor never offers it.
      it 'drops the averaging interval for a sensor that carries no number' do
        survey = described_class.new(sensor_name: 'wallbox_car_connected').call
        page = survey['pages'].find { |p| p['name'] == 'p_mqtt_write' }

        expect(page['elements'].pluck('name')).to eq(%w[mqtt_dedup mqtt_heartbeat_interval])
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

    describe 'the data type of an MQTT sensor' do
      let(:extraction_page) { result['pages'].find { |p| p['name'] == 'p_mqtt_extraction_value' } }

      # Every sensor carries either a measurement, a yes/no answer or a status
      # text, so the type is derived instead of asked for. A wrong answer used
      # to be unfixable, because InfluxDB binds a field to its first type.
      it 'is not asked for' do
        expect(extraction_page['elements'].pluck('name')).not_to include('mqtt_payload_type')
      end

      it 'explains a stored type the sensor would not pick' do
        with_config_yaml(
          'sensors' => {
            'custom_power_03' => { 'source' => 'mqtt', 'mqtt_topic' => 'oven', 'mqtt_payload_type' => 'integer' },
          },
        )
        note = extraction_page['elements'].find { |element| element['name'] == 'mqtt_type_note' }

        expect(note['html']).to include('default' => a_string_including('Integer'),
                                        'de' => a_string_including('Ganzzahl'))
      end

      it 'says nothing while the stored type matches the sensor' do
        with_config_yaml(
          'sensors' => {
            'custom_power_03' => { 'source' => 'mqtt', 'mqtt_topic' => 'oven', 'mqtt_payload_type' => 'float' },
          },
        )

        expect(extraction_page['elements'].pluck('name')).not_to include('mqtt_type_note')
      end
    end

    describe 'the total generation sensor' do
      def source_page(sensor_name)
        survey = described_class.new(sensor_name:).call
        survey['pages'].find { |page| page['name'] == 'p_source' }
      end

      it 'says that the total and the single producers are alternatives' do
        expect(source_page('inverter_power')['description']).to include(
          'default' => a_string_including('PV generator 1 to 5'),
          'de' => a_string_including('PV-Erzeuger 1 bis 5'),
        )
      end

      it 'leaves the generic description on every other sensor' do
        expect(source_page('inverter_power_1')['description']).to eq(
          source_page('custom_power_03')['description'],
        )
      end

      it 'names the SENEC total as a PV string once SENEC is set up' do
        with_config_yaml('senec' => { 'host' => '192.168.1.10' })

        expect(source_page('inverter_power')['description']).to include(
          'default' => a_string_including('PV generator 1 can read the total generation'),
          'de' => a_string_including('PV-Erzeuger 1 dafür die Gesamterzeugung'),
        )
      end

      it 'leaves the SENEC total out without SENEC' do
        expect(source_page('inverter_power')['description']['de']).not_to include('SENEC')
      end
    end

    # The SENEC collector writes each string and the total, so a PV string can
    # read either one.
    describe 'the SENEC field of a PV string' do
      def senec_field(sensor_name)
        find_survey_element(described_class.new(sensor_name:).call, 'senec_field')
      end

      it 'offers the string and the total of the system' do
        element = senec_field('inverter_power_2')

        aggregate_failures do
          expect(element['choices'].pluck('value')).to eq(%w[mpp2_power inverter_power])
          expect(element['defaultValue']).to eq('mpp2_power')
          expect(element['visibleIf']).to eq("{source} = 'senec'")
        end
      end

      it 'accepts the total while no other sensor reads it' do
        expect(senec_field('inverter_power_2')).not_to have_key('validators')
      end

      it 'refuses the total in the form while another sensor reads it' do
        with_config_yaml('sensors' => { 'inverter_power' => { 'source' => 'senec' } })

        expect(senec_field('inverter_power_2')['validators'].sole).to include(
          'type' => 'expression',
          'expression' => "{senec_field} <> 'inverter_power'",
          'text' => a_hash_including(
            'de' => 'Die Gesamterzeugung von SENEC ist bereits „Gesamte PV-Erzeugung“ zugeordnet.',
          ),
        )
      end

      it 'refuses SENEC for the total sensor while a PV string reads the total' do
        with_config_yaml('sensors' => { 'inverter_power_1' => { 'source' => 'senec', 'field' => 'inverter_power' } })
        survey = described_class.new(sensor_name: 'inverter_power').call

        expect(find_survey_element(survey, 'source')['validators'].sole).to include(
          'expression' => "{source} <> 'senec'",
          'text' => a_hash_including(
            'default' => 'The total generation of SENEC is already assigned to "PV generator 1".',
          ),
        )
      end

      it 'leaves SENEC open for the total sensor while no PV string reads the total' do
        survey = described_class.new(sensor_name: 'inverter_power').call

        expect(find_survey_element(survey, 'source')).not_to have_key('validators')
      end

      it 'asks only on a PV string SENEC can deliver' do
        expect(senec_field('inverter_power_4')).to be_nil
        expect(senec_field('inverter_power')).to be_nil
      end
    end

    # A sensor reads through a source, and a source only reads once it is set
    # up. Offering one that is off would let a sensor bring a source into
    # being, which is a decision of the data sources screen alone.
    describe 'the sources a sensor is offered' do
      def offered_sources(survey)
        find_survey_element(survey, 'source')['choices'].pluck('value')
      end

      it 'leaves out a source that is switched off' do
        expect(offered_sources(result)).to eq(%w[external])
      end

      it 'adds a source as soon as it is switched on' do
        with_config_yaml('shelly' => { 'connection' => 'local' })

        expect(offered_sources(result)).to eq(%w[shelly external])
      end

      # Switching a source off does not reach the sensors that read through
      # it. Dropping it from the form of such a sensor would rewrite its
      # source on the next save, without a word.
      it 'keeps the source the sensor already reads through' do
        with_config_yaml('sensors' => { 'custom_power_03' => { 'source' => 'mqtt' } })

        expect(offered_sources(result)).to eq(%w[mqtt external])
      end

      it 'says where the missing sources come from' do
        expect(find_survey_element(result, 'source')['description']).to include(
          'default' => a_string_including('Data Sources'),
          'de' => a_string_including('Datenquellen'),
        )
      end

      it 'says nothing while every source is on offer' do
        with_config_yaml(
          'shelly' => { 'connection' => 'local' },
          'mqtt' => { 'host' => 'broker.local' },
        )

        expect(offered_sources(result)).to eq(%w[shelly mqtt external])
        expect(find_survey_element(result, 'source')['description']).to be_nil
      end
    end

    describe 'source choices in dashboard_only mode' do
      before { with_config_yaml('deployment' => { 'mode' => 'dashboard_only' }) }

      it 'offers only the sources a dashboard-only stack can serve' do
        element = find_survey_element(result, 'source')

        expect(element['choices'].pluck('value')).to all(be_in(Configuration::DASHBOARD_ONLY_SOURCES))
      end

      it 'explains why the device collectors are missing' do
        element = find_survey_element(result, 'source')

        expect(element['description']).to include('default' => a_string_including('dashboard-only mode'),
                                                  'de' => a_string_including('Geräte-Kollektoren'))
      end
    end
  end
end
