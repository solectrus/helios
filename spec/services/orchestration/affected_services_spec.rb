RSpec.describe Orchestration::AffectedServices do
  describe '.compute' do
    let(:expected_hashes) do
      {
        'redis' => 'aaa111',
        'influxdb' => 'bbb222',
        'dashboard' => 'ccc333',
        'helios' => 'ddd444',
      }
    end

    before do
      described_class.invalidate_cache
      allow(Orchestration::Runner).to receive(:config_hashes).and_return(
        expected_hashes,
      )
    end

    context 'when all containers match expected hashes' do
      before do
        allow(Orchestration::Container).to receive(:all).and_return(
          [
            mock_container('redis', 'aaa111'),
            mock_container('influxdb', 'bbb222'),
            mock_container('dashboard', 'ccc333'),
            mock_container('helios', 'ddd444'),
          ],
        )
      end

      it 'returns empty array' do
        expect(described_class.compute).to eq([])
      end
    end

    context 'when a container has a different config hash' do
      before do
        allow(Orchestration::Container).to receive(:all).and_return(
          [
            mock_container('redis', 'aaa111'),
            mock_container('influxdb', 'old_hash'),
            mock_container('dashboard', 'ccc333'),
            mock_container('helios', 'ddd444'),
          ],
        )
      end

      it 'returns the mismatched service' do
        expect(described_class.compute).to eq(['influxdb'])
      end
    end

    context 'when multiple containers have different hashes' do
      before do
        allow(Orchestration::Container).to receive(:all).and_return(
          [
            mock_container('redis', 'old_redis'),
            mock_container('influxdb', 'old_influx'),
            mock_container('dashboard', 'ccc333'),
            mock_container('helios', 'ddd444'),
          ],
        )
      end

      it 'returns all mismatched services' do
        expect(described_class.compute).to contain_exactly('redis', 'influxdb')
      end
    end

    context 'when a service has no running container' do
      before do
        allow(Orchestration::Container).to receive(:all).and_return(
          [
            mock_container('redis', 'aaa111'),
            # influxdb not running
            mock_container('dashboard', 'ccc333'),
            mock_container('helios', 'ddd444'),
          ],
        )
      end

      it 'excludes services without containers' do
        expect(described_class.compute).to eq([])
      end
    end

    context 'when helios has a different hash' do
      before do
        allow(Orchestration::Container).to receive(:all).and_return(
          [
            mock_container('redis', 'aaa111'),
            mock_container('influxdb', 'bbb222'),
            mock_container('dashboard', 'ccc333'),
            mock_container('helios', 'different_hash'),
          ],
        )
      end

      it 'excludes helios from affected services' do
        expect(described_class.compute).to eq([])
      end
    end

    context 'when docker compose command fails' do
      before do
        allow(Orchestration::Runner).to receive(:config_hashes).and_raise(
          Orchestration::Runner::CommandError,
          'command failed',
        )
      end

      it 'returns empty array' do
        expect(described_class.compute).to eq([])
      end
    end

    context 'when docker connection fails' do
      before do
        allow(Orchestration::Container).to receive(:all).and_raise(
          Orchestration::ConnectionError,
          'cannot connect',
        )
      end

      it 'returns empty array' do
        expect(described_class.compute).to eq([])
      end
    end
  end

  private

  def mock_container(name, hash)
    instance_double(
      Orchestration::Container,
      service_name: name,
      config_hash: hash,
    )
  end
end
