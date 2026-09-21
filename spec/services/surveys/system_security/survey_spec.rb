RSpec.describe Surveys::SystemSecurity::Survey do
  describe '#call' do
    subject(:result) { described_class.new.call }

    before { with_config_yaml }

    # One question per screen, like every other form of the Settings screen.
    it 'asks one question per page' do
      pages = Array(result['pages'])

      expect(pages.map { |page| page['elements'].pluck('name') })
        .to eq([%w[admin_password], %w[lockup_codeword], %w[frame_ancestors]])
    end

    it 'exposes the admin_password field as required' do
      expect(find_survey_element(result, 'admin_password')).to include('isRequired' => true)
    end

    it 'exposes the optional lockup_codeword field alongside the admin password' do
      element = find_survey_element(result, 'lockup_codeword')
      expect(element).to be_present
      expect(element).not_to include('isRequired' => true)
    end

    # Who may embed the dashboard is a question about who reaches the
    # interface, so it is asked next to the passwords.
    it 'asks who may embed the dashboard' do
      element = find_survey_element(result, 'frame_ancestors')
      expect(element).to be_present
      expect(element).not_to include('isRequired' => true)
    end
  end
end
