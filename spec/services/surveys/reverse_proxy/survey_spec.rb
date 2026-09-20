RSpec.describe Surveys::ReverseProxy::Survey do
  describe '#call' do
    subject(:result) { described_class.new.call }

    before { with_config_yaml }

    # The domain is the one thing an external proxy cannot be set up without,
    # and nothing else supplies it. So the form that chooses that mode asks for
    # it, rather than sending the reader to the network screen for the answer.
    it 'asks for the domain on the page that chooses the external proxy' do
      page = Array(result['pages']).find { |p| p['name'] == 'p_external' }

      expect(page['elements'].pluck('name')).to include('app_host')
      expect(find_survey_element(result, 'app_host')).to include('isRequired' => true)
    end

    # The same rule as on the network screen: the address has to name the
    # machine to others.
    it 'refuses an address that names the machine to itself' do
      validator = find_survey_element(result, 'app_host')['validators'].first

      expect(validator).to include('type' => 'regex', 'caseInsensitive' => true)
      expect(validator['regex']).to eq(HostAddress::SURVEY_PATTERN)
    end

    # The address bar of the browser names the domain an external proxy routes
    # nowhere: it carries the address HELIOS itself is reached at. An offer
    # here would fill a required field with the one value it must not hold.
    it 'takes no address from the browser' do
      expect(result).not_to have_key('offerBrowserHost')
    end
  end
end
