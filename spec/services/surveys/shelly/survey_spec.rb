RSpec.describe Surveys::Shelly::Survey do
  describe '#call' do
    subject(:result) { described_class.new.call }

    it 'no longer carries an image page (channel choice lives in the software survey)' do
      expect(section_names(result)).not_to include('p_image')
    end
  end
end
