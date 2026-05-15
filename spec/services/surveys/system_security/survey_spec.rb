RSpec.describe Surveys::SystemSecurity::Survey do
  describe '#call' do
    subject(:result) { described_class.new.call }

    before { with_config_yaml }

    it 'exposes the admin_password field as required' do
      expect(find_survey_element(result, 'admin_password')).to include('isRequired' => true)
    end

    it 'exposes the optional lockup_codeword field alongside the admin password' do
      element = find_survey_element(result, 'lockup_codeword')
      expect(element).to be_present
      expect(element).not_to include('isRequired' => true)
    end
  end
end
