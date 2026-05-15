RSpec.describe Surveys::DashboardCo2::Survey do
  describe '#call' do
    subject(:result) { described_class.new.call }

    it 'exposes the CO2 emission factor with the German grid mix as default' do
      expect(find_survey_element(result, 'co2_emission_factor')).to include(
        'defaultValue' => '401',
        'inputType' => 'number',
      )
    end
  end
end
