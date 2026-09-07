RSpec.describe Orchestration::Container do
  describe '.all' do
    before { skip_without_docker }

    it 'queries the daemon and filters by project name' do
      expect(described_class.all(project: 'nonexistent-project-xyz')).to eq([])
    end
  end
end
