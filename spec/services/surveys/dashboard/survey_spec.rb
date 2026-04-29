RSpec.describe Surveys::Dashboard::Survey do
  describe '#call' do
    subject(:result) { described_class.new.call }

    let(:image_element) do
      result['pages']
        .find { |p| p['name'] == 'p_image' }
        &.dig('elements')
        &.find { |e| e['name'] == 'image' }
    end

    context 'when the registry exposes multiple versions (default DASHBOARD)' do
      it 'fills the image element choices with the current image first' do
        expect(image_element['choices'].first).to include(
          'value' => DockerImages.current(:DASHBOARD),
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
          .to eq(DockerImages::DASHBOARD[:current].pluck(:image))
      end
    end

    context 'when the registry only exposes a single version' do
      before do
        stub_const(
          'DockerImages::DASHBOARD',
          { current: 'ghcr.io/solectrus/solectrus:latest' }.freeze,
        )
      end

      it 'drops the version page entirely so the user is not shown a one-option chooser' do
        expect(result['pages'].pluck('name')).not_to include('p_image')
      end
    end
  end
end
