RSpec.describe SupportBundle::ContainerLogs do
  describe '.filename_for' do
    it 'uses the compose service name when available' do
      container = instance_double(
        Orchestration::Container,
        service_name: 'dashboard',
        name: 'solectrus-dashboard-1',
        id: 'abc123def456',
      )

      expect(described_class.filename_for(container)).to eq('logs/dashboard.log')
    end

    it 'falls back to the container name when service label is missing' do
      container = instance_double(
        Orchestration::Container,
        service_name: nil,
        name: 'standalone-app',
        id: 'abc123def456',
      )

      expect(described_class.filename_for(container)).to eq('logs/standalone-app.log')
    end

    it 'falls back to the short container id as last resort' do
      container = instance_double(
        Orchestration::Container,
        service_name: nil,
        name: nil,
        id: 'abc123def456789',
      )

      expect(described_class.filename_for(container)).to eq('logs/abc123def456.log')
    end

    it 'sanitizes unsafe characters in the filename' do
      container = instance_double(
        Orchestration::Container,
        service_name: 'weird/name with space',
        name: nil,
        id: 'abc',
      )

      expect(described_class.filename_for(container)).to eq('logs/weird_name_with_space.log')
    end
  end

  describe '.collect' do
    it 'returns an error entry when Docker is not reachable' do
      allow(Orchestration::Container).to receive(:all).and_raise(
        Orchestration::ConnectionError.new('Cannot connect to Docker'),
      )

      result = described_class.collect

      expect(result.keys).to eq(['logs/_error.txt'])
      expect(result['logs/_error.txt']).to include('Docker unavailable')
    end
  end
end
