RSpec.describe Surveys::DashboardTheme::Survey do
  describe '#call' do
    subject(:result) { described_class.new.call }

    it 'exposes ui_theme as a radiogroup with user-selectable plus fixed light/dark choices' do
      element = find_survey_element(result, 'ui_theme')
      expect(element).to include('type' => 'radiogroup')
      expect(element['choices'].pluck('value')).to contain_exactly('user', 'light', 'dark')
    end
  end
end
