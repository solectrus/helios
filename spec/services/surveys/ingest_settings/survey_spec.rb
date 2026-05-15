RSpec.describe Surveys::IngestSettings::Survey do
  describe '#call' do
    subject(:result) { described_class.new.call }

    it 'exposes the retention_hours element with a sensible default' do
      expect(find_survey_element(result, 'retention_hours')).to include(
        'defaultValue' => '12',
        'inputType' => 'number',
      )
    end
  end
end
