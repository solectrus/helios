RSpec.describe Orchestration::AffectedServices do
  let(:deployed_hashes_path) { described_class.deployed_hashes_path }
  let(:fingerprints_path) { Orchestration::ConfigFingerprints.path }
  let(:services) { {} }

  before do
    FileUtils.rm_f([deployed_hashes_path, fingerprints_path])
    allow(Orchestration::Runner).to receive(:config_services) { services }
  end

  after do
    described_class.invalidate_cache
    FileUtils.rm_f([deployed_hashes_path, fingerprints_path])
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

      it 'updates the hash when the applied hash matches the current config' do
        described_class.update_deployed_hash!('redis', applied_hash: 'new_redis')

        stored = JSON.parse(File.read(deployed_hashes_path))
        expect(stored['redis']).to eq('new_redis')
      end

      # Watchtower recreates a container from its old config, so the
      # label still carries the old hash.
      it 'keeps the old hash when the container runs an older config' do
        described_class.update_deployed_hash!('redis', applied_hash: 'old_redis')

        stored = JSON.parse(File.read(deployed_hashes_path))
        expect(stored['redis']).to eq('old_redis')
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

      # A restart marker that cannot be updated is a cosmetic problem; the
      # manual restart itself already happened.
      it 'swallows a compose command that fails' do
        allow(Orchestration::Runner).to receive(:config_hashes)
          .and_raise(Orchestration::Runner::CommandError, 'command failed')

        expect { described_class.update_deployed_hash!('redis') }.not_to raise_error

        stored = JSON.parse(File.read(deployed_hashes_path))
        expect(stored['redis']).to eq('old_redis')
      end

      it 'swallows a baseline file that cannot be written' do
        allow(described_class).to receive(:write_deployed_hashes_file!).and_raise(Errno::EACCES)

        expect { described_class.new.send(:write_deployed_hashes, {}) }.not_to raise_error
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

  describe 'the reason for a restart' do
    let(:hashes) { { 'dashboard' => 'h1', 'helios' => 'h0' } }
    let(:services) do
      { 'dashboard' => { 'image' => 'solectrus:latest', 'environment' => { 'INFLUX_TOKEN' => 'a' } } }
    end

    before do
      allow(Orchestration::Runner).to receive(:config_hashes) { hashes }
    end

    def change_env
      services['dashboard']['environment']['INFLUX_SENSOR_HOUSE_POWER'] = 'SENEC:house_power'
      hashes['dashboard'] = 'h2'
    end

    it 'is known after a deploy of the whole stack' do
      described_class.store_deployed_hashes!
      change_env

      expect(described_class.change_for('dashboard').added).to eq(['INFLUX_SENSOR_HOUSE_POWER'])
    end

    it 'is known after a deploy of a single service' do
      write_deployed_hashes('dashboard' => 'h0')
      described_class.update_deployed_hash!('dashboard')
      change_env

      expect(described_class.change_for('dashboard').added).to eq(['INFLUX_SENSOR_HOUSE_POWER'])
    end

    it 'is known after the first baseline' do
      described_class.seed_baseline_if_missing!
      change_env

      expect(described_class.change_for('dashboard').added).to eq(['INFLUX_SENSOR_HOUSE_POWER'])
    end

    it 'is known after the lazy baseline of the first compute' do
      allow(Orchestration::Container).to receive(:all).and_return([])
      described_class.compute
      change_env

      expect(described_class.change_for('dashboard').added).to eq(['INFLUX_SENSOR_HOUSE_POWER'])
    end

    it 'is known when the fingerprint is taken before a config change' do
      write_deployed_hashes('dashboard' => 'h1')
      described_class.seed_baseline_if_missing!
      change_env

      expect(described_class.change_for('dashboard').added).to eq(['INFLUX_SENSOR_HOUSE_POWER'])
    end

    it 'is unknown when the config changed before the first fingerprint' do
      write_deployed_hashes('dashboard' => 'h1')
      change_env
      described_class.sync_fingerprints!

      expect(described_class.change_for('dashboard')).to be_nil
    end

    it 'takes no fingerprint without a deployed baseline' do
      described_class.sync_fingerprints!

      expect(File.exist?(fingerprints_path)).to be(false)
    end

    it 'does not ask compose when every fingerprint is current' do
      described_class.store_deployed_hashes!
      described_class.invalidate_config_hashes

      described_class.sync_fingerprints!

      expect(Orchestration::Runner).to have_received(:config_hashes).once
    end

    it 'logs a failing compose call while fingerprinting' do
      write_deployed_hashes('dashboard' => 'h1')
      allow(Orchestration::Runner).to receive(:config_hashes).and_raise(
        Orchestration::Runner::CommandError, 'boom'
      )

      expect { described_class.sync_fingerprints! }.not_to raise_error
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
