RSpec.describe DockerHost::Container do
  let(:mock_container) do
    instance_double(
      Docker::Container,
      id: 'abc123def456',
      info: {
        'Names' => ['/solectrus-dashboard-1'],
        'Image' => 'ghcr.io/solectrus/solectrus:latest',
        'State' => 'running',
        'Created' => '2024-01-15T10:00:00.000000000Z',
        'Ports' => [{ 'PrivatePort' => 3000, 'PublicPort' => 3000 }],
        'Labels' => {
          'com.docker.compose.project' => 'solectrus',
          'com.docker.compose.service' => 'dashboard',
        },
      },
      json: {
        'State' => {
          'Health' => {
            'Status' => 'healthy',
          },
        },
      },
    )
  end

  let(:container) { described_class.new(mock_container) }

  describe '.all' do
    context 'when Docker is available' do
      before { skip_without_docker }

      it 'returns an array of Container objects' do
        containers = described_class.all(project: 'nonexistent-project')
        expect(containers).to be_an(Array)
      end

      it 'filters by project name' do
        containers = described_class.all(project: 'nonexistent-project-xyz')
        expect(containers).to be_empty
      end
    end

    context 'when Docker is not available' do
      before do
        allow(Docker::Container).to receive(:all).and_raise(
          Excon::Error::Socket.new(StandardError.new('Connection refused')),
        )
      end

      it 'raises ConnectionError' do
        expect { described_class.all(project: 'test') }.to raise_error(
          DockerHost::ConnectionError,
        )
      end
    end
  end

  describe '.find' do
    context 'when Docker is available' do
      before { skip_without_docker }

      it 'returns nil for non-existent service' do
        container = described_class.find(
          'nonexistent-service',
          project: 'nonexistent-project',
        )
        expect(container).to be_nil
      end
    end
  end

  describe '#id' do
    it 'returns the container id' do
      expect(container.id).to eq('abc123def456')
    end
  end

  describe '#name' do
    it 'returns the container name without leading slash' do
      expect(container.name).to eq('solectrus-dashboard-1')
    end
  end

  describe '#service_name' do
    it 'returns the compose service name' do
      expect(container.service_name).to eq('dashboard')
    end
  end

  describe '#image' do
    it 'returns the image name' do
      expect(container.image).to eq('ghcr.io/solectrus/solectrus:latest')
    end
  end

  describe '#status' do
    it 'returns the container state' do
      expect(container.status).to eq('running')
    end
  end

  describe '#running?' do
    it 'returns true when container is running' do
      expect(container.running?).to be true
    end
  end

  describe '#health_status' do
    it 'returns the health status' do
      expect(container.health_status).to eq('healthy')
    end
  end

  describe '#healthy?' do
    it 'returns true when container is healthy' do
      expect(container.healthy?).to be true
    end
  end

  describe '#logs' do
    it 'returns container logs with default options' do
      allow(mock_container).to receive(:logs) do |opts|
        expect(opts).to eq(
          { stdout: true, stderr: true, tail: 100, timestamps: false },
        )
        "2024-01-15 10:00:00 App started\n"
      end

      expect(container.logs).to eq("2024-01-15 10:00:00 App started\n")
    end

    it 'accepts custom tail and timestamps options' do
      allow(mock_container).to receive(:logs) do |opts|
        expect(opts).to eq(
          { stdout: true, stderr: true, tail: 50, timestamps: true },
        )
        'log output'
      end

      expect(container.logs(tail: 50, timestamps: true)).to eq(
        'log output',
      )
    end

    it 'returns nil when container not found' do
      allow(mock_container).to receive(:logs).and_raise(
        Docker::Error::NotFoundError,
      )

      expect(container.logs).to be_nil
    end
  end

  describe '#to_h' do
    it 'returns a hash representation' do
      hash = container.to_h
      expect(hash).to include(
        id: 'abc123def456',
        name: 'solectrus-dashboard-1',
        service_name: 'dashboard',
        status: 'running',
        health_status: 'healthy',
      )
    end
  end
end
