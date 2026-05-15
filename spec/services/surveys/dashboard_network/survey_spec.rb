RSpec.describe Surveys::DashboardNetwork::Survey do
  describe '#call' do
    subject(:result) { described_class.new.call }

    it 'exposes the network fields' do
      expect(find_survey_element(result, 'frame_ancestors')).to be_present
      expect(find_survey_element(result, 'host_port')).to include(
        'defaultValue' => '3000',
        'inputType' => 'number',
      )
    end

    it 'no longer exposes trusted_proxy_ranges (moved to the reverse-proxy survey)' do
      expect(find_survey_element(result, 'trusted_proxy_ranges')).to be_nil
    end
  end
end
