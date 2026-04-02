RSpec.describe Orchestration do
  describe '.connected?' do
    it 'returns true when Docker is available' do
      skip_without_docker
      expect(described_class.connected?).to be true
    end
  end

  describe '.default_project' do
    it 'derives project name from stack path' do
      allow(Rails.configuration).to receive(:data_path).and_return(
        '/data',
      )
      expect(described_class.default_project).to eq('data')
    end
  end
end
