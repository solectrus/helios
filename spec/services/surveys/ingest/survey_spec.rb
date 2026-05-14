RSpec.describe Surveys::Ingest::Survey do
  describe '#call' do
    subject(:result) { described_class.new.call }

    let(:image_element) do
      result['pages']
        .find { |p| p['name'] == 'p_image' }
        &.dig('elements')
        &.find { |e| e['name'] == 'image' }
    end

    context 'when the registry exposes multiple versions (default INGEST)' do
      it 'fills the image element choices with the current image first' do
        expect(image_element['choices'].first).to include(
          'value' => DockerImages.current(:INGEST),
        )
      end

      it 'translates registry labels to SurveyJS-style locale hashes (default + de)' do
        text = image_element['choices'].first['text']
        expect(text.keys).to contain_exactly('default', 'de')
        expect(text['default']).to be_present
        expect(text['de']).to be_present
      end

      it 'includes every selectable variant from the registry' do
        expect(image_element['choices'].pluck('value'))
          .to eq(DockerImages::INGEST[:current].pluck(:image))
      end
    end

    context 'when the registry only exposes a single version' do
      before do
        stub_const(
          'DockerImages::INGEST',
          { current: 'ghcr.io/solectrus/ingest:latest' }.freeze,
        )
      end

      it 'drops the version page entirely so the user is not shown a one-option chooser' do
        expect(result['pages'].pluck('name')).not_to include('p_image')
      end
    end

    it 'exposes a retention_hours element with a sensible default' do
      element = result['pages']
                .find { |p| p['name'] == 'p_settings' }
                &.dig('elements')
                &.find { |e| e['name'] == 'retention_hours' }
      expect(element).to include('defaultValue' => '12', 'inputType' => 'number')
    end
  end
end
