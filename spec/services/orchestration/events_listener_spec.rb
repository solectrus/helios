RSpec.describe Orchestration::EventsListener do
  # Characterization specs for the class-level singleton lifecycle. They pin
  # the observable behaviour (start/stop/restart, subscriber counting, locale,
  # abandon) so the lifecycle can be refactored onto a shared base class without
  # changing what the class does. A lightweight instance double stands in for a
  # real listener so no Docker-listening threads are spawned.
  let(:fake_instance) do
    instance_double(
      described_class,
      start: nil,
      stop: nil,
      running?: true,
      mark_stopped!: nil,
    )
  end

  def reset_storage!
    DOCKER_EVENTS_STORAGE[:instance] = nil
    DOCKER_EVENTS_STORAGE[:subscriber_count] = 0
    DOCKER_EVENTS_STORAGE[:last_restart] = nil
  end

  before do
    reset_storage!
    described_class.initialize_lifecycle
    allow(described_class).to receive(:new).and_return(fake_instance)
  end

  after { reset_storage! }

  describe '.running?' do
    it 'is falsey without an instance' do
      expect(described_class).not_to be_running
    end

    it 'reflects the instance once started' do
      described_class.start
      expect(described_class.running?).to be(true)
    end
  end

  describe '.start' do
    it 'creates and starts an instance' do
      described_class.start

      aggregate_failures do
        expect(described_class).to have_received(:new).once
        expect(fake_instance).to have_received(:start)
      end
    end

    it 'is idempotent while already running' do
      described_class.start
      described_class.start

      expect(described_class).to have_received(:new).once
    end
  end

  describe '.stop' do
    it 'stops the instance and clears it' do
      described_class.start
      described_class.stop

      aggregate_failures do
        expect(fake_instance).to have_received(:stop)
        expect(described_class).not_to be_running
      end
    end

    it 'is a no-op without an instance' do
      expect { described_class.stop }.not_to raise_error
    end
  end

  describe '.restart' do
    it 'replaces the running instance' do
      described_class.start
      described_class.restart

      aggregate_failures do
        expect(fake_instance).to have_received(:stop)
        expect(described_class).to have_received(:new).twice
      end
    end

    it 'skips a restart within the cooldown window' do
      described_class.start
      described_class.restart
      described_class.restart

      # initial start + first restart only; the second restart is cooled down
      expect(described_class).to have_received(:new).twice
    end
  end

  describe 'subscriber tracking' do
    it 'starts on the first subscriber and counts it' do
      described_class.subscriber_connected

      aggregate_failures do
        expect(described_class.subscriber_count).to eq(1)
        expect(fake_instance).to have_received(:start)
      end
    end

    it 'stops when the last subscriber disconnects' do
      described_class.subscriber_connected
      described_class.subscriber_disconnected

      aggregate_failures do
        expect(described_class.subscriber_count).to eq(0)
        expect(fake_instance).to have_received(:stop)
      end
    end

    it 'never drops below zero' do
      described_class.subscriber_disconnected
      expect(described_class.subscriber_count).to eq(0)
    end

    it 'resets the count on demand' do
      described_class.subscriber_connected
      described_class.reset_subscriber_count!
      expect(described_class.subscriber_count).to eq(0)
    end
  end

  describe '.locale' do
    it 'defaults to the I18n default locale' do
      expect(described_class.locale).to eq(I18n.default_locale)
    end

    it 'remembers the locale supplied by a subscriber' do
      described_class.subscriber_connected(locale: :de)
      expect(described_class.locale).to eq(:de)
    end
  end

  describe '.stop_abandoned' do
    it 'marks the listener stopped and clears class state' do
      described_class.subscriber_connected
      listener = DOCKER_EVENTS_STORAGE[:instance]

      described_class.stop_abandoned(listener)

      aggregate_failures do
        expect(listener).to have_received(:mark_stopped!)
        expect(described_class).not_to be_running
        expect(described_class.subscriber_count).to eq(0)
      end
    end

    it 'ignores a listener that is no longer the current instance' do
      described_class.start
      other = instance_double(described_class, mark_stopped!: nil)

      described_class.stop_abandoned(other)

      aggregate_failures do
        expect(other).not_to have_received(:mark_stopped!)
        expect(described_class.running?).to be(true)
      end
    end
  end

  # Before this, a leftover container whose service compose.yaml no longer
  # knows produced three failed broadcasts per event, and the next event
  # started over. The broadcaster now reports it and the sweep removes it.
  describe 'an event for a service compose.yaml no longer knows' do
    include ActiveSupport::Testing::TimeHelpers

    let(:listener) { described_class.new }
    let(:broadcaster) { instance_double(Orchestration::ServiceBroadcaster) }

    let(:event) do
      instance_double(
        Orchestration::Event,
        relevant?: true,
        helios_operation?: false,
        service_name: 'db',
        action: 'start',
      )
    end

    # A broadcast falls due BROADCAST_DELAY after its event, and both the
    # broadcast and the sweep run on the scheduler thread, so a tick past that
    # delay has to follow the event. Two seconds, because `travel` truncates
    # to whole seconds and one would land short of the delay often enough.
    def process_and_tick(times: 1)
      times.times { listener.send(:process_event, event) }
      travel(2.seconds) { listener.send(:run_scheduler_tick) }
    end

    before do
      # The outer `before` stubs `new` away so no Docker threads spawn; this
      # block needs a real instance.
      allow(described_class).to receive(:new).and_call_original
      allow(Orchestration::ServiceBroadcaster).to receive(:new).and_return(broadcaster)
      allow(Orchestration::OrphanedServices).to receive(:prune!)
    end

    context 'when the service is still in compose.yaml' do
      before { allow(broadcaster).to receive(:broadcast).and_return(true) }

      it 'leaves the container alone' do
        process_and_tick

        expect(Orchestration::OrphanedServices).not_to have_received(:prune!)
      end
    end

    context 'when the service is gone from compose.yaml' do
      before { allow(broadcaster).to receive(:broadcast).and_return(:unknown_service) }

      it 'sweeps the leftover container away' do
        process_and_tick

        expect(Orchestration::OrphanedServices).to have_received(:prune!)
      end

      # Retrying cannot bring the service back into compose.yaml, so the three
      # failed broadcasts per event have to stop.
      it 'does not retry the broadcast' do
        process_and_tick
        travel(20.seconds) { listener.send(:run_scheduler_tick) }

        expect(broadcaster).to have_received(:broadcast).once
      end

      # A leftover container under `restart: always` emits events faster than
      # the sweep returns, so the tick has to coalesce them.
      it 'sweeps once for a burst of events' do
        process_and_tick(times: 3)

        expect(Orchestration::OrphanedServices).to have_received(:prune!).once
      end

      it 'does not sweep again on a tick without a new event' do
        process_and_tick
        listener.send(:run_scheduler_tick)

        expect(Orchestration::OrphanedServices).to have_received(:prune!).once
      end

      # The removal emits stop/die/destroy events of its own, and each of them
      # would otherwise arm another sweep that can only find the same claim.
      it 'asks for no sweep while the removal is already queued' do
        Orchestration::PendingOperations.set('db', :remove)
        process_and_tick

        expect(Orchestration::OrphanedServices).not_to have_received(:prune!)
      end
    end
  end
end
