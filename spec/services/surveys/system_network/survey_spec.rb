RSpec.describe Surveys::SystemNetwork::Survey do
  describe '#call' do
    subject(:result) { described_class.new.call }

    before { with_config_yaml }

    it 'exposes the app_host field' do
      expect(find_survey_element(result, 'app_host')).to include('isRequired' => true)
    end
  end
end
