RSpec.describe Orchestration::DetachedContainers do
  def container(service:, networks:, network_mode: 'solectrus_default', state: 'exited',
                one_off: false)
    info = {
      'Names' => ["/solectrus-#{service}-1"],
      'State' => state,
      'HostConfig' => { 'NetworkMode' => network_mode },
      'NetworkSettings' => { 'Networks' => networks },
      'Labels' => {
        'com.docker.compose.service' => service,
        'com.docker.compose.oneoff' => one_off ? 'True' : 'False',
      },
    }
    Orchestration::Container.new(
      instance_double(Docker::Container, id: "id-#{service}", info: info),
    )
  end

  # What an interrupted `up` leaves behind: the container exists and carries
  # the right network mode, but was never connected, so nothing inside it can
  # resolve another service.
  let(:containers) { [container(service: 'dashboard', networks: {})] }

  before do
    # spec/support/detached_containers.rb stubs the sweep out everywhere, so
    # that no spec touches the developer's own stack. Here it is the subject.
    allow(described_class).to receive(:sweep).and_call_original
    allow(Orchestration::DockerCli).to receive(:force_remove_container).and_return([true, ''])
    allow(Orchestration::Container).to receive_messages(all: containers, invalidate_cache: nil)
  end

  # Once to see the containers as they are now, once because the removal made
  # that view stale again.
  it 'removes a container that hangs in no network and drops the cached state' do
    described_class.sweep

    aggregate_failures do
      expect(Orchestration::DockerCli).to have_received(:force_remove_container)
        .with('id-dashboard')
      expect(Orchestration::Container).to have_received(:invalidate_cache).twice
    end
  end

  # What the interrupted `up` actually leaves: created, never started, never
  # connected.
  context 'with a container that was created but never started' do
    let(:containers) { [container(service: 'dashboard', networks: {}, state: 'created')] }

    it 'removes it' do
      described_class.sweep

      expect(Orchestration::DockerCli).to have_received(:force_remove_container)
        .with('id-dashboard')
    end
  end

  context 'with a connected container' do
    let(:containers) do
      [container(service: 'dashboard', networks: { 'solectrus_default' => { 'IPAddress' => '172.18.0.2' } })]
    end

    it 'leaves it alone and drops the cache no second time' do
      described_class.sweep

      aggregate_failures do
        expect(Orchestration::DockerCli).not_to have_received(:force_remove_container)
        expect(Orchestration::Container).to have_received(:invalidate_cache).once
      end
    end
  end

  # `up <service>` starts that service and its dependencies, so a detached
  # container of any service would be revived as-is by the very next start.
  context 'with several services detached' do
    let(:containers) do
      [
        container(service: 'dashboard', networks: {}),
        container(service: 'redis', networks: {}),
      ]
    end

    it 'removes every one of them' do
      described_class.sweep

      aggregate_failures do
        expect(Orchestration::DockerCli).to have_received(:force_remove_container)
          .with('id-dashboard')
        expect(Orchestration::DockerCli).to have_received(:force_remove_container)
          .with('id-redis')
      end
    end
  end

  # Compose builds a running container anew as soon as an `up` covers it, and
  # killing one that no `up` covers would leave nothing behind at all.
  context 'with a running detached container' do
    let(:containers) { [container(service: 'dashboard', networks: {}, state: 'running')] }

    it 'leaves it to compose' do
      described_class.sweep

      expect(Orchestration::DockerCli).not_to have_received(:force_remove_container)
    end
  end

  # Removing HELIOS' own container would take the interface away, and no `up`
  # would build it back.
  context 'with the HELIOS container detached' do
    let(:containers) { [container(service: 'helios', networks: {})] }

    it 'leaves it alone' do
      described_class.sweep

      expect(Orchestration::DockerCli).not_to have_received(:force_remove_container)
    end
  end

  # A one-off container of `compose run` sits unconnected between its creation
  # and its start, and belongs to no service the stack keeps.
  context 'with a one-off container' do
    let(:containers) { [container(service: 'postgresql', networks: {}, one_off: true)] }

    it 'leaves it alone' do
      described_class.sweep

      expect(Orchestration::DockerCli).not_to have_received(:force_remove_container)
    end
  end

  # `host`, `none` and `container:` carry no network entry either, but mean it.
  # An unreadable mode must not cost a container either.
  ['host', 'none', 'container:abc123', nil].each do |mode|
    context "with network mode #{mode.inspect}" do
      let(:containers) { [container(service: 'dashboard', networks: {}, network_mode: mode)] }

      it 'leaves the container alone' do
        described_class.sweep

        expect(Orchestration::DockerCli).not_to have_received(:force_remove_container)
      end
    end
  end

  # The compose command that follows reports a broken Docker far better than
  # this sweep could, so it stays quiet and removes nothing.
  [
    [Orchestration::ConnectionError, 'Cannot connect to Docker'],
    [Docker::Error::DockerError, 'Something went wrong'],
  ].each do |error, message|
    context "when Docker raises #{error}" do
      before { allow(Orchestration::Container).to receive(:all).and_raise(error, message) }

      it 'stays quiet and removes nothing' do
        aggregate_failures do
          expect { described_class.sweep }.not_to raise_error
          expect(Orchestration::DockerCli).not_to have_received(:force_remove_container)
        end
      end
    end
  end
end
