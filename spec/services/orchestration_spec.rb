RSpec.describe Orchestration do
  describe '.connected?' do
    it 'returns true when Docker is available' do
      skip_without_docker
      expect(described_class.connected?).to be true
    end
  end

  describe '.default_project' do
    it 'returns COMPOSE_PROJECT_NAME if set' do
      allow(ENV).to receive(:fetch).with(
        'COMPOSE_PROJECT_NAME',
        nil,
      ).and_return('my-project')
      expect(described_class.default_project).to eq('my-project')
    end

    it 'derives project name from stack path' do
      allow(ENV).to receive(:fetch).with(
        'COMPOSE_PROJECT_NAME',
        nil,
      ).and_return(nil)
      allow(Rails.configuration).to receive(:data_path).and_return(
        '/data',
      )
      expect(described_class.default_project).to eq('data')
    end
  end
end
