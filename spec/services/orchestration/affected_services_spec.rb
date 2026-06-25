RSpec.describe Orchestration::AffectedServices do
  let(:deployed_hashes_path) { described_class.deployed_hashes_path }

  before { FileUtils.rm_f(deployed_hashes_path) }

  after do
    described_class.invalidate_cache
    FileUtils.rm_f(deployed_hashes_path)
  end

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

    context 'when no deployed hashes exist (first run)' do
      before do
        allow(Orchestration::Container).to receive(:all).and_return(
          [
            mock_container('redis', 'anything'),
            mock_container('influxdb', 'anything'),
          ],
        )
      end

      it 'returns empty array and stores current hashes as deployed' do
        expect(described_class.compute).to eq([])
        expect(File.exist?(deployed_hashes_path)).to be(true)
      end
    end

    context 'when expected hashes match deployed hashes' do
      before do
        write_deployed_hashes(
          'redis' => 'aaa111',
          'influxdb' => 'bbb222',
          'dashboard' => 'ccc333',
        )
        allow(Orchestration::Container).to receive(:all).and_return(
          [
            mock_container('redis', 'any_container_hash'),
            mock_container('influxdb', 'any_container_hash'),
            mock_container('dashboard', 'any_container_hash'),
          ],
        )
      end

      it 'returns empty array regardless of container labels' do
        expect(described_class.compute).to eq([])
      end
    end

    context 'when expected hash differs from deployed hash' do
      before do
        write_deployed_hashes(
          'redis' => 'aaa111',
          'influxdb' => 'old_deployed_hash',
          'dashboard' => 'ccc333',
        )
        allow(Orchestration::Container).to receive(:all).and_return(
          [
            mock_container('redis', 'any'),
            mock_container('influxdb', 'any'),
            mock_container('dashboard', 'any'),
          ],
        )
      end

      it 'returns the mismatched service' do
        expect(described_class.compute).to eq(['influxdb'])
      end
    end

    context 'when multiple expected hashes differ from deployed' do
      before do
        write_deployed_hashes(
          'redis' => 'old_redis',
          'influxdb' => 'old_influx',
          'dashboard' => 'ccc333',
        )
        allow(Orchestration::Container).to receive(:all).and_return(
          [
            mock_container('redis', 'any'),
            mock_container('influxdb', 'any'),
            mock_container('dashboard', 'any'),
          ],
        )
      end

      it 'returns all mismatched services' do
        expect(described_class.compute).to contain_exactly('redis', 'influxdb')
      end
    end

    context 'when a service has no running container' do
      before do
        write_deployed_hashes(
          'redis' => 'aaa111',
          'influxdb' => 'old_hash',
          'dashboard' => 'ccc333',
        )
        allow(Orchestration::Container).to receive(:all).and_return(
          [
            mock_container('redis', 'any'),
            # influxdb not running
            mock_container('dashboard', 'any'),
          ],
        )
      end

      it 'excludes services without containers' do
        expect(described_class.compute).to eq([])
      end
    end

    context 'when helios has a different hash' do
      before do
        write_deployed_hashes(
          'redis' => 'aaa111',
          'influxdb' => 'bbb222',
          'dashboard' => 'ccc333',
        )
        allow(Orchestration::Container).to receive(:all).and_return(
          [
            mock_container('redis', 'any'),
            mock_container('influxdb', 'any'),
            mock_container('dashboard', 'any'),
            mock_container('helios', 'any'),
          ],
        )
      end

      it 'excludes helios from affected services' do
        expect(described_class.compute).to eq([])
      end
    end

    context 'when a new service is added (not in deployed hashes)' do
      before do
        write_deployed_hashes(
          'redis' => 'aaa111',
          'dashboard' => 'ccc333',
        )
        allow(Orchestration::Container).to receive(:all).and_return(
          [
            mock_container('redis', 'any'),
            mock_container('influxdb', 'any'),
            mock_container('dashboard', 'any'),
          ],
        )
      end

      it 'flags the new service as affected' do
        expect(described_class.compute).to eq(['influxdb'])
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
        write_deployed_hashes('redis' => 'aaa111')
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

  describe '.seed_baseline_if_missing!' do
    before do
      described_class.invalidate_cache
      allow(Orchestration::Runner).to receive(:config_hashes).and_return(
        'redis' => 'aaa111',
        'dashboard' => 'ccc333',
        'helios' => 'ddd444',
      )
    end

    context 'when no baseline file exists' do
      it 'writes the current hashes (excluding helios) as the baseline' do
        described_class.seed_baseline_if_missing!

        stored = JSON.parse(File.read(deployed_hashes_path))
        expect(stored).to eq('redis' => 'aaa111', 'dashboard' => 'ccc333')
      end
    end

    context 'when a baseline file already exists' do
      before { write_deployed_hashes('redis' => 'old_redis') }

      it 'leaves the existing baseline untouched' do
        described_class.seed_baseline_if_missing!

        stored = JSON.parse(File.read(deployed_hashes_path))
        expect(stored).to eq('redis' => 'old_redis')
      end
    end

    context 'when docker compose command fails' do
      before do
        allow(Orchestration::Runner).to receive(:config_hashes).and_raise(
          Orchestration::Runner::CommandError,
          'command failed',
        )
      end

      it 'does not create a baseline file' do
        described_class.seed_baseline_if_missing!

        expect(File.exist?(deployed_hashes_path)).to be(false)
      end
    end

    # Reproduces the bug where a config change made before any baseline existed
    # (e.g. right after import, which performs no deploy) was swallowed: seeding
    # the pre-change config first makes the subsequent change detectable.
    context 'when used to bracket a config change' do
      let(:dashboard_container) do
        [
          mock_container('redis', 'any'),
          mock_container('dashboard', 'any'),
        ]
      end

      before do
        allow(Orchestration::Container).to receive(:all).and_return(
          dashboard_container,
        )
      end

      it 'flags the service changed after the baseline was seeded' do
        # Pre-change state becomes the baseline.
        described_class.seed_baseline_if_missing!

        # Config change: dashboard hash differs now.
        described_class.invalidate_cache
        allow(Orchestration::Runner).to receive(:config_hashes).and_return(
          'redis' => 'aaa111',
          'dashboard' => 'CHANGED',
          'helios' => 'ddd444',
        )

        expect(described_class.compute).to eq(['dashboard'])
      end
    end
  end

  describe '.update_deployed_hash!' do
    let(:expected_hashes) do
      {
        'redis' => 'new_redis',
        'influxdb' => 'bbb222',
        'helios' => 'ddd444',
      }
    end

    before do
      described_class.invalidate_cache
      allow(Orchestration::Runner).to receive(:config_hashes).and_return(
        expected_hashes,
      )
    end

    context 'when deployed hashes exist' do
      before do
        write_deployed_hashes(
          'redis' => 'old_redis',
          'influxdb' => 'bbb222',
        )
      end

      it 'updates the hash for the specified service' do
        described_class.update_deployed_hash!('redis')

        stored = JSON.parse(File.read(deployed_hashes_path))
        expect(stored['redis']).to eq('new_redis')
      end

      it 'preserves hashes of other services' do
        described_class.update_deployed_hash!('redis')

        stored = JSON.parse(File.read(deployed_hashes_path))
        expect(stored['influxdb']).to eq('bbb222')
      end

      it 'does not update when hash already matches' do
        described_class.update_deployed_hash!('influxdb')

        stored = JSON.parse(File.read(deployed_hashes_path))
        expect(stored).to eq('redis' => 'old_redis', 'influxdb' => 'bbb222')
      end

      it 'prunes entries for services no longer in compose.yaml' do
        write_deployed_hashes(
          'redis' => 'old_redis',
          'influxdb' => 'bbb222',
          'obsolete' => 'xxx',
        )

        described_class.update_deployed_hash!('redis')

        stored = JSON.parse(File.read(deployed_hashes_path))
        expect(stored).not_to have_key('obsolete')
      end
    end

    context 'when service is not in expected hashes' do
      it 'does not modify deployed hashes' do
        write_deployed_hashes('redis' => 'old_redis')

        described_class.update_deployed_hash!('unknown')

        stored = JSON.parse(File.read(deployed_hashes_path))
        expect(stored).to eq('redis' => 'old_redis')
      end
    end

    context 'when no deployed hashes file exists' do
      it 'does not create the file' do
        described_class.update_deployed_hash!('redis')

        expect(File.exist?(deployed_hashes_path)).to be(false)
      end
    end
  end

  describe '.store_deployed_hashes!' do
    let(:hashes) do
      { 'redis' => 'abc', 'influxdb' => 'def', 'helios' => 'ghi' }
    end

    before do
      allow(Orchestration::Runner).to receive(:config_hashes).and_return(hashes)
    end

    it 'writes hashes (excluding helios) to the deployed hashes file' do
      described_class.store_deployed_hashes!

      stored = JSON.parse(File.read(deployed_hashes_path))
      expect(stored).to eq('redis' => 'abc', 'influxdb' => 'def')
    end

    it 'invalidates the affected services cache' do
      described_class.store_deployed_hashes!

      # Verify cache was populated with fresh hashes
      expect(Orchestration::Runner).to have_received(:config_hashes).once
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

  def write_deployed_hashes(hashes)
    FileUtils.mkdir_p(File.dirname(deployed_hashes_path))
    File.write(deployed_hashes_path, hashes.to_json)
  end
end
