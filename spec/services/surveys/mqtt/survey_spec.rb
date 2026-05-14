RSpec.describe Surveys::Mqtt::Survey do
  describe '#call' do
    subject(:result) { described_class.new.call }

    let(:image_element) do
      result['pages']
        .find { |p| p['name'] == 'p_image' }
        &.dig('elements')
        &.find { |e| e['name'] == 'image' }
    end

    context 'when the registry exposes multiple versions (default MQTT_COLLECTOR)' do
      it 'appends the image page as the last page so existing fields stay on top' do
        expect(result['pages'].last['name']).to eq('p_image')
      end

      it 'fills the image element choices with the current image first' do
        expect(image_element['choices'].first).to include(
          'value' => DockerImages.current(:MQTT_COLLECTOR),
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
          .to eq(DockerImages::MQTT_COLLECTOR[:current].pluck(:image))
      end

      it 'preselects the recommended (first) variant so fresh setups default to latest' do
        expect(image_element['defaultValue']).to eq(DockerImages.current(:MQTT_COLLECTOR))
      end
    end

    context 'when the registry only exposes a single version' do
      before do
        stub_const(
          'DockerImages::MQTT_COLLECTOR',
          { current: 'ghcr.io/solectrus/mqtt-collector:latest' }.freeze,
        )
      end

      it 'drops the version page entirely so the user is not shown a one-option chooser' do
        expect(result['pages'].pluck('name')).not_to include('p_image')
      end
    end
  end
end
