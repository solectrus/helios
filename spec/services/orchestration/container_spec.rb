RSpec.describe Orchestration::Container do
  let(:mock_container) do
    instance_double(
      Docker::Container,
      id: 'abc123def456',
      info: {
        'Names' => ['/solectrus-dashboard-1'],
        'Image' => 'ghcr.io/solectrus/solectrus:develop',
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
    context 'when Docker is not available' do
      before do
        allow(Docker::Container).to receive(:all).and_raise(
          Excon::Error::Socket.new(StandardError.new('Connection refused')),
        )
      end

      it 'raises ConnectionError' do
        expect { described_class.all(project: 'test') }.to raise_error(
          Orchestration::ConnectionError,
        )
      end
    end
  end

  describe '.find' do
    before { allow(described_class).to receive(:fetch_all_containers).and_return([mock_container]) }

    it 'picks the container carrying the compose service label' do
      expect(described_class.find('dashboard', project: 'solectrus')&.id).to eq('abc123def456')
    end

    it 'returns nil when no container carries the label' do
      expect(described_class.find('influxdb', project: 'solectrus')).to be_nil
    end
  end

  describe '#config_hash' do
    it 'reads the compose config hash off the labels, and is nil without one' do
      expect(container.config_hash).to be_nil

      allow(mock_container).to receive(:info).and_return(
        mock_container.info.deep_merge('Labels' => { 'com.docker.compose.config-hash' => 'deadbeef' }),
      )
      expect(container.config_hash).to eq('deadbeef')
    end
  end

  # Docker leaves the tag off when the image was pulled by digest or is
  # implicitly :latest.
  describe '#image_tag' do
    { 'ghcr.io/solectrus/solectrus:develop' => 'develop', 'alpine' => 'latest', nil => nil }
      .each do |image, tag|
      it "reads #{tag.inspect} from #{image.inspect}" do
        allow(mock_container).to receive(:info).and_return(mock_container.info.merge('Image' => image))

        expect(container.image_tag).to eq(tag)
      end
    end
  end

  describe '#version' do
    # An unreachable daemon must not take the service row down; the row then
    # simply shows no version.
    it 'is nil when the daemon cannot be asked' do
      allow(Orchestration::VersionExtractor).to receive(:extract)
        .and_raise(Excon::Error::Socket.new(StandardError.new('gone')))

      expect(container.version).to be_nil
    end
  end

  describe '#healthcheck_configured?' do
    # The inspect data is read once per container, so each case needs its own.
    it 'follows what the container declares' do
      expect(container).to be_healthcheck_configured
    end

    it 'is false without a healthcheck' do
      allow(mock_container).to receive(:json).and_return('State' => {})

      expect(container).not_to be_healthcheck_configured
    end

    # One container going away must not cascade into a failing service list.
    it 'is false when the container cannot be inspected at all' do
      allow(mock_container).to receive(:json).and_raise(Docker::Error::NotFoundError)

      expect(container).not_to be_healthcheck_configured
      expect(container.mount_source('/data')).to be_nil
    end
  end

  describe '#exec, #kill and #created_at' do
    # Despite its name, #kill only sends a signal — the power-splitter uses
    # USR1 to recalculate, and stays up.
    it 'passes them through to Docker' do
      allow(mock_container).to receive_messages(exec: [['out'], [], 0], kill!: nil)

      expect(container.exec(%w[echo hi])).to eq([['out'], [], 0])
      container.kill(signal: :USR1)

      expect(mock_container).to have_received(:exec).with(%w[echo hi])
      expect(mock_container).to have_received(:kill!).with('signal' => 'USR1')
      expect(container.created_at).to eq(Time.utc(2024, 1, 15, 10, 0, 0))
    end
  end

  describe '#mount_source' do
    it 'returns the host path behind a destination, and nil for an unmounted one' do
      allow(mock_container).to receive(:json).and_return(
        'Mounts' => [{ 'Destination' => '/data', 'Source' => '/opt/solectrus' }],
      )

      expect(container.mount_source('/data')).to eq('/opt/solectrus')
      expect(container.mount_source('/nowhere')).to be_nil
    end
  end

  describe '#stop_and_remove!' do
    it 'stops the container before removing it' do
      allow(mock_container).to receive(:stop)
      allow(mock_container).to receive(:remove)

      container.stop_and_remove!

      expect(mock_container).to have_received(:stop).ordered
      expect(mock_container).to have_received(:remove).ordered
    end
  end

  describe '#inspect' do
    it 'names the service, its status and its health' do
      expect(container.inspect).to eq('#<Orchestration::Container dashboard: running (healthy)>')
    end

    it 'leaves the health out when the container declares none' do
      allow(mock_container).to receive(:json).and_return('State' => {})

      expect(container.inspect).to eq('#<Orchestration::Container dashboard: running>')
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
      expect(container.image).to eq('ghcr.io/solectrus/solectrus:develop')
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

  describe '#crash_looping?' do
    def container_in_state(state, restart_count, finished_at: 1.hour.ago,
                           started_at: 1.hour.ago)
      raw = instance_double(
        Docker::Container,
        id: 'abc123def456',
        info: mock_container.info.merge('State' => state),
        json: {
          'RestartCount' => restart_count,
          'State' => {
            'StartedAt' => started_at.iso8601(9),
            'FinishedAt' => finished_at.iso8601(9),
            'Health' => { 'Status' => 'starting' },
          },
        },
      )
      described_class.new(raw)
    end

    it 'reports a container that waits between attempts as crash looping' do
      subject = container_in_state('restarting', 7)

      aggregate_failures do
        expect(subject.restart_count).to eq(7)
        expect(subject).to be_crash_looping
      end
    end

    # A time HELIOS cannot parse must never flag a container — it says
    # nothing about whether it just died.
    it 'does not report a container whose exit time is unreadable' do
      raw = instance_double(
        Docker::Container,
        id: 'abc123def456',
        info: mock_container.info.merge('State' => 'running'),
        json: { 'RestartCount' => 7, 'State' => { 'FinishedAt' => 'not a time' } },
      )

      expect(described_class.new(raw)).not_to be_crash_looping
    end

    # The first restarts after a crash are indistinguishable from a slow
    # start, so they must keep the ordinary starting indicator.
    it 'does not report the first restarts as crash looping' do
      expect(container_in_state('restarting', 1)).not_to be_crash_looping
    end

    # Docker's restart backoff starts at 100 ms, so a service that dies two
    # seconds into its boot is reported as `running` most of the time. Read
    # literally, that turns a dying service green.
    it 'reports a running container that just died as crash looping' do
      subject =
        container_in_state('running', 7, finished_at: 2.seconds.ago,
                                         started_at: 1.second.ago)

      expect(subject).to be_crash_looping
    end

    # A container that crash looped an hour ago but recovered keeps its
    # restart count forever — only a recent exit makes it a loop.
    it 'does not report a container that stayed up as crash looping' do
      subject = container_in_state('running', 7)

      aggregate_failures do
        expect(subject.restart_count).to eq(7)
        expect(subject).not_to be_crash_looping
      end
    end

    # What a host reboot leaves behind: the restart policy brings the container
    # up again, so StartedAt is seconds old while RestartCount still carries
    # the loop it survived weeks ago. Read off StartedAt, every service that
    # ever looped would come back from a reboot flagged.
    it 'does not report a rebooted container with an old count as crash looping' do
      subject =
        container_in_state('running', 7, finished_at: 1.hour.ago,
                                         started_at: 2.seconds.ago)

      expect(subject).not_to be_crash_looping
    end

    it 'treats a missing restart count as zero' do
      expect(container.restart_count).to eq(0)
    end
  end

  describe '#health_status' do
    def container_with_health(status, failing_streak, state: 'running', log: [])
      raw = instance_double(
        Docker::Container,
        id: 'abc123def456',
        info: mock_container.info.merge('State' => state),
        json: {
          'State' => {
            'Health' => {
              'Status' => status,
              'FailingStreak' => failing_streak,
              'Log' => log,
            },
          },
        },
      )
      described_class.new(raw)
    end

    it 'returns the health status' do
      expect(container.health_status).to eq('healthy')
    end

    # Pausing a container stops its health monitor: Docker flips the status to
    # `unhealthy` without a single probe having failed, and it stays that way
    # until the next interval after `unpause`. Reporting that as a fault turned
    # the whole stack red for a few seconds after every update pause.
    it 'reads unhealthy without a failing streak as not yet probed' do
      subject = container_with_health('unhealthy', 0)

      aggregate_failures do
        expect(subject.health_status).to eq('starting')
        expect(subject.effective_status).to eq(:starting)
      end
    end

    # The log survives the pause, so the last successful probe is still on
    # record while Docker reports the frozen `unhealthy`. Without it the whole
    # stack would sit at `starting` for a full interval after every thaw.
    it 'reads unhealthy with a passing probe on record as healthy' do
      subject = container_with_health('unhealthy', 0, log: [{ 'ExitCode' => 1 }, { 'ExitCode' => 0 }])

      aggregate_failures do
        expect(subject.health_status).to eq('healthy')
        expect(subject.effective_status).to eq(:ok)
      end
    end

    # A container frozen inside its start period can have a failed probe on
    # record with the streak still at zero — not yet a fault, but not passing
    # either.
    it 'reads unhealthy with a failed probe on record as not yet probed' do
      subject = container_with_health('unhealthy', 0, log: [{ 'ExitCode' => 1 }])

      aggregate_failures do
        expect(subject.health_status).to eq('starting')
        expect(subject.effective_status).to eq(:starting)
      end
    end

    it 'keeps unhealthy once a probe has actually failed' do
      subject = container_with_health('unhealthy', 1)

      aggregate_failures do
        expect(subject.health_status).to eq('unhealthy')
        expect(subject.effective_status).to eq(:error)
      end
    end

    # The pause itself must still read as stopped-on-purpose, not as starting.
    it 'reports a paused container as stopped regardless of its health' do
      subject = container_with_health('unhealthy', 0, state: 'paused')

      expect(subject.effective_status).to eq(:stopped)
    end
  end

  describe 'inspect caching' do
    around do |example|
      original_store = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      example.run
    ensure
      Rails.cache = original_store
    end

    it 'shares inspect data across instances with the same container id' do
      first = described_class.new(mock_container)
      first.health_status

      second_raw = instance_double(Docker::Container, id: mock_container.id)
      allow(second_raw).to receive(:json)
      second = described_class.new(second_raw)

      expect(second.health_status).to eq('healthy')
      expect(second_raw).not_to have_received(:json)
    end

    it 'forces a fresh inspect after invalidate_cache' do
      first = described_class.new(mock_container)
      first.health_status

      described_class.invalidate_cache

      fresh_raw =
        instance_double(
          Docker::Container,
          id: mock_container.id,
          # A failed probe on record, so the value survives #health_status's
          # "unhealthy without a failing streak means not yet probed" reading
          # and this example keeps testing the cache rather than that rule.
          json: {
            'State' => { 'Health' => { 'Status' => 'unhealthy', 'FailingStreak' => 3 } },
          },
        )
      second = described_class.new(fresh_raw)

      expect(second.health_status).to eq('unhealthy')
      expect(fresh_raw).to have_received(:json)
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

  # Guards the cold-cache coalescing in fetch_all_containers: the lazy-loaded
  # /services page fires N row requests at once, and without the lock each
  # would run its own Docker::Container.all on a cold cache.
  describe 'cold-cache coalescing' do
    # A real store (the suite default is :null_store, which never caches, so
    # the second thread could never see the first's result).
    let(:memory_cache) { ActiveSupport::Cache::MemoryStore.new }

    # A named, marshalable stand-in for the raw Docker::Container — MemoryStore
    # marshals its entries, and RSpec doubles carry singleton methods that
    # can't be dumped (real Docker::Container objects can).
    let(:raw_class) { stub_const('FakeRawContainer', Struct.new(:id, :info, :json)) }
    let(:raw_container) do
      raw_class.new(
        'abc123def456',
        {
          'Labels' => {
            'com.docker.compose.project' => 'solectrus',
            'com.docker.compose.service' => 'dashboard',
          },
        },
        {},
      )
    end

    before do
      allow(Rails).to receive(:cache).and_return(memory_cache)
      allow(Orchestration::Connection).to receive(:configure!)
    end

    it 'runs Docker::Container.all once for concurrent cold reads' do
      docker_calls = Concurrent::AtomicFixnum.new(0)
      allow(Docker::Container).to receive(:all) do
        docker_calls.increment
        sleep 0.05 # hold the lock long enough for the others to queue on it
        [raw_container]
      end

      # Concurrency is the whole point here — spawn simultaneous cold reads.
      threads =
        Array.new(5) do
          Thread.new { described_class.all(project: 'solectrus') } # rubocop:disable ThreadSafety/NewThread
        end

      expect(threads.map(&:value)).to all(
        contain_exactly(an_instance_of(described_class)),
      )
      expect(docker_calls.value).to eq(1)
    end

    it 'skips Docker entirely once the cache is warm' do
      allow(Docker::Container).to receive(:all).and_return([raw_container])

      described_class.all(project: 'solectrus') # cold → one call
      described_class.all(project: 'solectrus') # warm → served from cache

      expect(Docker::Container).to have_received(:all).once
    end
  end
end
