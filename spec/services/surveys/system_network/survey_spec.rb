RSpec.describe Surveys::SystemNetwork::Survey do
  describe '#call' do
    subject(:result) { described_class.new.call }

    before { with_config_yaml }

    # Not mandatory: an installation that names no address is a state of its
    # own, and every caller falls back to the published port alone.
    it 'exposes the app_host field without demanding an answer' do
      expect(find_survey_element(result, 'app_host')).to include('name' => 'app_host', 'type' => 'text')
      expect(find_survey_element(result, 'app_host')).not_to have_key('isRequired')
    end

    # Refused where it is typed, rather than after the survey has closed.
    it 'refuses an address that names the machine to itself' do
      validator = find_survey_element(result, 'app_host')['validators'].first

      expect(validator).to include('type' => 'regex', 'caseInsensitive' => true)
      expect(validator['regex']).to eq(HostAddress::SURVEY_PATTERN)
    end
  end
end
