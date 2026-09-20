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

    # This form asks for the address of this machine, which is what the address
    # bar of the browser holds, so the field may be offered that address.
    it 'lets the browser offer the address it was reached at' do
      expect(result).to include('offerBrowserHost' => true)
    end

    # Behind an external reverse proxy the address is the domain that proxy
    # routes, and the form choosing that mode asks for it there. This screen
    # keeps asking the same question it always did, and keeps taking no answer.
    it 'demands no answer behind an external reverse proxy either' do
      with_config_yaml('reverse_proxy' => { 'mode' => 'external', 'bind_ip' => '10.0.0.5' })

      expect(find_survey_element(result, 'app_host')).not_to have_key('isRequired')
    end
  end
end
