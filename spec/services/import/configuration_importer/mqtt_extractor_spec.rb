RSpec.describe Import::ConfigurationImporter::MqttExtractor do
  subject(:extractor) { described_class.new(reader, {}) }

  let(:reader) { instance_double(Import::StackReader, services: { 'mqtt-collector' => {} }, service: service) }
  let(:service) { { 'environment' => env } }

  describe 'sign-based splitting (MEASUREMENT_POSITIVE/NEGATIVE)' do
    context 'with plain payload split' do
      let(:env) do
        {
          'MAPPING_0_TOPIC' => 'senec/0/ENERGY/GUI_GRID_POW',
          'MAPPING_0_TYPE' => 'float',
          'MAPPING_0_MEASUREMENT_POSITIVE' => 'PV',
          'MAPPING_0_FIELD_POSITIVE' => 'grid_import_power',
          'MAPPING_0_MEASUREMENT_NEGATIVE' => 'PV',
          'MAPPING_0_FIELD_NEGATIVE' => 'grid_export_power',
        }
      end

      it 'expands into two mappings with correct measurement/field pairs' do
        expect(extractor.mappings).to contain_exactly(
          hash_including(measurement: 'PV', field: 'grid_import_power'),
          hash_including(measurement: 'PV', field: 'grid_export_power'),
        )
      end

      it 'adds a FORMULA that keeps only positive values for the positive variant' do
        positive = extractor.mappings.find { |m| m[:field] == 'grid_import_power' }
        expect(positive[:formula]).to eq('IF({value} > 0, {value}, 0)')
      end

      it 'adds a FORMULA that flips sign for the negative variant' do
        negative = extractor.mappings.find { |m| m[:field] == 'grid_export_power' }
        expect(negative[:formula]).to eq('IF({value} < 0, -{value}, 0)')
      end

      it 'preserves topic and type on both variants' do
        extractor.mappings.each do |m|
          expect(m[:topic]).to eq('senec/0/ENERGY/GUI_GRID_POW')
          expect(m[:type]).to eq('float')
        end
      end

      it 'does not leak the split keys' do
        extractor.mappings.each do |m|
          expect(m.keys).not_to include(
            :measurement_positive, :measurement_negative,
            :field_positive, :field_negative
          )
        end
      end
    end

    context 'with JSON key split' do
      let(:env) do
        {
          'MAPPING_0_TOPIC' => 'grid/status',
          'MAPPING_0_TYPE' => 'float',
          'MAPPING_0_JSON_KEY' => 'power',
          'MAPPING_0_MEASUREMENT_POSITIVE' => 'Grid',
          'MAPPING_0_FIELD_POSITIVE' => 'import',
          'MAPPING_0_MEASUREMENT_NEGATIVE' => 'Grid',
          'MAPPING_0_FIELD_NEGATIVE' => 'export',
        }
      end

      it 'rewrites JSON_KEY into a JSON_FORMULA referencing that key' do
        positive = extractor.mappings.find { |m| m[:field] == 'import' }
        expect(positive[:json_formula]).to eq('IF({power} > 0, {power}, 0)')
        expect(positive[:json_key]).to be_nil
      end

      it 'does the same for the negative variant' do
        negative = extractor.mappings.find { |m| m[:field] == 'export' }
        expect(negative[:json_formula]).to eq('IF({power} < 0, -{power}, 0)')
        expect(negative[:json_key]).to be_nil
      end
    end

    context 'with only one side configured' do
      let(:env) do
        {
          'MAPPING_0_TOPIC' => 'grid/pow',
          'MAPPING_0_TYPE' => 'float',
          'MAPPING_0_MEASUREMENT_POSITIVE' => 'PV',
          'MAPPING_0_FIELD_POSITIVE' => 'grid_import_power',
        }
      end

      it 'emits only the configured variant' do
        expect(extractor.mappings.size).to eq(1)
        expect(extractor.mappings.first).to include(
          measurement: 'PV',
          field: 'grid_import_power',
          formula: 'IF({value} > 0, {value}, 0)',
        )
      end
    end

    context 'with JSONPath split' do
      let(:env) do
        {
          'MAPPING_0_TOPIC' => 'go-e/ATTR',
          'MAPPING_0_TYPE' => 'float',
          'MAPPING_0_JSON_PATH' => '$.ccp[0]',
          'MAPPING_0_MEASUREMENT_POSITIVE' => 'Grid',
          'MAPPING_0_FIELD_POSITIVE' => 'import',
          'MAPPING_0_MEASUREMENT_NEGATIVE' => 'Grid',
          'MAPPING_0_FIELD_NEGATIVE' => 'export',
        }
      end

      it 'rewrites JSON_PATH into a JSON_FORMULA referencing that path' do
        positive = extractor.mappings.find { |m| m[:field] == 'import' }
        expect(positive[:json_formula]).to eq('IF({$.ccp[0]} > 0, {$.ccp[0]}, 0)')
        expect(positive[:json_path]).to be_nil
      end
    end

    context 'with an existing JSON_FORMULA split' do
      let(:env) do
        {
          'MAPPING_0_TOPIC' => 'hp/state',
          'MAPPING_0_TYPE' => 'float',
          'MAPPING_0_JSON_FORMULA' => '{power} / 1000',
          'MAPPING_0_MEASUREMENT_POSITIVE' => 'HP',
          'MAPPING_0_FIELD_POSITIVE' => 'p',
          'MAPPING_0_MEASUREMENT_NEGATIVE' => 'HP',
          'MAPPING_0_FIELD_NEGATIVE' => 'n',
        }
      end

      it 'wraps the existing JSON formula in a sign-filter IF' do
        positive = extractor.mappings.find { |m| m[:field] == 'p' }
        expect(positive[:json_formula]).to eq('IF(({power} / 1000) > 0, ({power} / 1000), 0)')
      end
    end

    context 'without splitting' do
      let(:env) do
        {
          'MAPPING_0_TOPIC' => 'house/power',
          'MAPPING_0_TYPE' => 'float',
          'MAPPING_0_MEASUREMENT' => 'House',
          'MAPPING_0_FIELD' => 'power',
        }
      end

      it 'passes the mapping through unchanged' do
        expect(extractor.mappings).to contain_exactly(
          { topic: 'house/power', type: 'float', measurement: 'House', field: 'power' },
        )
      end
    end
  end
end
