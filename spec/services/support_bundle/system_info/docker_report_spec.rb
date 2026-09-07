RSpec.describe SupportBundle::SystemInfo::DockerReport do
  describe '.fetch_snapshot' do
    it 'collects daemon info, version and containers in one snapshot' do
      containers = [instance_double(Docker::Container)]
      allow(Orchestration::Connection).to receive(:configure!)
      allow(Docker).to receive_messages(info: { 'ID' => 'abc' }, version: { 'Version' => '27.0' })
      allow(Docker::Container).to receive(:all).with(all: true).and_return(containers)

      expect(described_class.fetch_snapshot).to eq(
        info: { 'ID' => 'abc' },
        version: { 'Version' => '27.0' },
        containers:,
      )
    end

    # A bundle collected while the daemon is down must still be produced; the
    # Docker sections then carry the error instead of failing the whole run.
    it 'reports an unreachable daemon as an error entry' do
      allow(Orchestration::Connection).to receive(:configure!)
      allow(Docker).to receive(:info).and_raise(Excon::Error::Socket.new(StandardError.new('no socket')))

      expect(described_class.fetch_snapshot[:error]).to start_with('unavailable: Excon::Error::Socket')
    end
  end

  describe '.engine' do
    it 'reports version, API version, platform and storage driver' do
      snapshot = {
        version: { 'Version' => '27.0.3', 'ApiVersion' => '1.46', 'Os' => 'linux', 'Arch' => 'arm64' },
        info: { 'Driver' => 'overlay2' },
      }

      expect(described_class.engine(snapshot)).to eq(
        'Version' => '27.0.3',
        'API version' => '1.46',
        'OS/Arch' => 'linux/arm64',
        'Storage driver' => 'overlay2',
      )
    end

    it 'shows the snapshot error as the status' do
      expect(described_class.engine(error: 'unavailable: boom')).to eq('Status' => 'unavailable: boom')
    end
  end

  describe '.compose' do
    it 'reports the version of the compose plugin' do
      allow(SupportBundle::SystemInfo::OutputFormatter)
        .to receive(:capture).with('docker', 'compose', 'version', '--short').and_return('2.32.4')

      expect(described_class.compose).to eq('Version' => '2.32.4')
    end
  end

  describe '.containers' do
    it 'passes the snapshot error through' do
      expect(described_class.containers(error: 'unavailable: boom')).to eq('unavailable: boom')
    end

    it 'reports an empty daemon instead of an empty table' do
      expect(described_class.containers(containers: [])).to eq('No containers found.')
    end

    it 'counts the containers and lists the running ones first' do
      snapshot = {
        containers: [
          fake_container('influxdb', { 'solectrus_default' => {} },
                         state: 'exited', status: 'Exited (0) 2 hours ago', image: 'influxdb:2.7'),
          fake_container('helios', { 'default' => {}, 'solectrus_default' => {} },
                         state: 'running', status: 'Up 3 minutes', image: 'ghcr.io/solectrus/helios'),
        ],
      }

      result = described_class.containers(snapshot)
      rows = result.lines.map(&:strip)

      expect(rows.first).to eq('2 total (running: 1, stopped: 1)')
      expect(rows[3]).to start_with('helios')
      expect(rows[3]).to include('running', 'Up 3 minutes', 'default,solectrus_default')
      expect(rows[4]).to start_with('influxdb')
      expect(rows[4]).to include('exited', 'influxdb:2.7')
    end

    # A container started outside compose may carry no name; the short id is
    # the only handle support has on it, and it has no network of its own.
    it 'falls back to the short id and a dash for a nameless container' do
      nameless = instance_double(
        Docker::Container,
        info: { 'Id' => 'ab12cd34ef567890', 'State' => 'running', 'Status' => 'Up 1 second', 'Image' => 'busybox' },
      )

      result = described_class.containers(containers: [nameless])

      expect(result).to include('ab12cd34ef56')
      expect(result.lines.last).to match(/busybox\s+-/)
    end
  end

  describe '.networks' do
    it 'passes the snapshot error through' do
      expect(described_class.networks(error: 'unavailable: boom')).to eq('unavailable: boom')
    end

    it 'reports nothing to show when the daemon has no containers' do
      expect(described_class.networks(containers: [])).to eq('No networks found.')
    end

    it 'reports nothing to show when no container is attached to a network' do
      bare = instance_double(Docker::Container, info: { 'Names' => ['/orphan'] })

      expect(described_class.networks(containers: [bare])).to eq('No networks found.')
    end

    it 'lists each network with its member count and names' do
      snapshot = {
        containers: [
          fake_container('influxdb', { 'solectrus_default' => {} }),
          fake_container('dashboard', { 'solectrus_default' => {} }),
          fake_container('helios', { 'default' => {} }),
        ],
      }

      rows = described_class.networks(snapshot).lines.map(&:strip)

      expect(rows.first).to match(/NAME\s+CONTAINERS\s+NAMES/)
      expect(rows[1]).to match(/\Adefault\s+1\s+helios\z/)
      expect(rows[2]).to match(/\Asolectrus_default\s+2\s+dashboard, influxdb\z/)
    end
  end

  describe '.network_membership' do
    it 'groups containers by attached network' do
      containers = [
        fake_container('helios', { 'default' => {} }),
        fake_container('influxdb', { 'solectrus_default' => {} }),
        fake_container('dashboard', { 'solectrus_default' => {} }),
      ]

      expect(described_class.network_membership(containers)).to eq(
        'default' => ['helios'],
        'solectrus_default' => %w[influxdb dashboard],
      )
    end

    it 'lists a container under each network it is attached to' do
      containers = [fake_container('proxy', { 'frontend' => {}, 'backend' => {} })]

      expect(described_class.network_membership(containers)).to eq(
        'frontend' => ['proxy'],
        'backend' => ['proxy'],
      )
    end

    it 'ignores containers without network settings' do
      bare = instance_double(Docker::Container, info: { 'Names' => ['/orphan'] })

      expect(described_class.network_membership([bare])).to eq({})
    end
  end

  def fake_container(name, networks, state: 'running', status: 'Up 1 minute', image: 'alpine')
    instance_double(
      Docker::Container,
      info: {
        'Names' => ["/#{name}"],
        'State' => state,
        'Status' => status,
        'Image' => image,
        'NetworkSettings' => { 'Networks' => networks },
      },
    )
  end
end
