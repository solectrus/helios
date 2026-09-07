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

  describe '.fetch_log' do
    it 'repairs output that is not UTF-8' do
      allow(Open3).to receive(:capture2e).and_return(["Gr\xFCn\n", process_status])

      expect(described_class.fetch_log('abc123def456')).to eq("Grün\n")
    end

    it 'keeps the output of a failing docker logs call, with its exit code' do
      allow(Open3).to receive(:capture2e).and_return(["No such container\n", process_status(success: false)])

      expect(described_class.fetch_log('abc123def456')).to eq("failed (exit 1):\nNo such container\n")
    end

    it 'reports a missing docker binary instead of raising' do
      allow(Open3).to receive(:capture2e).and_raise(Errno::ENOENT, 'docker')

      expect(described_class.fetch_log('abc123def456')).to start_with('unavailable: Errno::ENOENT')
    end
  end

  describe '.collect' do
    it 'writes one log file per container in the project' do
      container = instance_double(
        Orchestration::Container, service_name: 'dashboard', name: 'solectrus-dashboard-1', id: 'abc123def456'
      )
      allow(Orchestration::Container).to receive(:all).and_return([container])
      allow(Open3).to receive(:capture2e).and_return(["booted\n", process_status])

      expect(described_class.collect).to eq('logs/dashboard.log' => "booted\n")
    end

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
