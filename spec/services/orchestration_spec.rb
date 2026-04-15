RSpec.describe Orchestration do
  describe 'PROJECT_NAME' do
    it 'is "solectrus"' do
      expect(Orchestration::PROJECT_NAME).to eq('solectrus')
    end
  end
end
