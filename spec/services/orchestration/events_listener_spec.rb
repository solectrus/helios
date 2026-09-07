RSpec.describe Orchestration::EventsListener do
  include ActiveSupport::Testing::TimeHelpers

  # The class-level specs below hand out `fake_instance`; the instance-level
  # ones restore the real constructor in their own `before` and use this.
  let(:listener) { described_class.new }

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
    # Without this, the locale a subscriber left behind leaks into the next
    # example and makes `.locale` order-dependent.
    DOCKER_EVENTS_STORAGE[:locale] = nil
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

  describe 'the event stream' do
    let(:broadcaster) { instance_double(Orchestration::ServiceBroadcaster, broadcast: true) }

    before do
      allow(described_class).to receive(:new).and_call_original
      allow(Orchestration::ServiceBroadcaster).to receive(:new).and_return(broadcaster)
      # Chunks are only consumed while the listener runs.
      listener.send(:instance_variable_get, :@running).make_true
    end

    # Docker writes its event stream in HTTP chunks that cut through JSON
    # objects; parsing per chunk would drop every event that spans two.
    it 'assembles an event that arrives split across chunks' do
      buffer = +''
      event = {
        'Type' => 'container', 'Action' => 'start',
        'Actor' => { 'Attributes' => { 'com.docker.compose.service' => 'db' } }
      }
      json = JSON.dump(event)

      listener.send(:process_chunk, buffer, json[0, 10])
      listener.send(:process_chunk, buffer, "#{json[10..]}\n")

      expect(broadcaster).not_to have_received(:broadcast)
      travel(2.seconds) { listener.send(:run_scheduler_tick) }
      expect(broadcaster).to have_received(:broadcast).with('db', created: nil)
    end

    it 'ignores a line that is not JSON' do
      buffer = +''

      expect { listener.send(:process_chunk, buffer, "not json\n") }.not_to raise_error
      expect(buffer).to eq('')
    end

    # A stream that never yields a newline would grow without bound; the
    # buffer is dropped rather than eating the whole heap.
    it 'drops a buffer that grows past the limit' do
      buffer = +''

      listener.send(:process_chunk, buffer, 'x' * (1.megabyte + 1))

      expect(buffer).to eq('')
    end

    it 'streams from the Docker events endpoint and feeds every chunk through' do
      block = nil
      connection = instance_double(Docker::Connection)
      allow(connection).to receive(:get) { |*, **opts| block = opts[:response_block] }
      allow(Docker).to receive(:connection).and_return(connection)

      listener.send(:stream_events)
      block.call("{}\n", nil, nil)

      expect(connection).to have_received(:get).with('/events', {}, hash_including(:response_block))
    end

    # A chunk that arrives after the listener was stopped is dropped rather
    # than broadcast into a shutdown.
    it 'ignores chunks once it has been stopped' do
      block = nil
      connection = instance_double(Docker::Connection)
      allow(connection).to receive(:get) { |*, **opts| block = opts[:response_block] }
      allow(Docker).to receive(:connection).and_return(connection)
      allow(listener).to receive(:process_chunk)

      listener.send(:stream_events)
      listener.mark_stopped!
      block.call("{}\n", nil, nil)

      expect(listener).not_to have_received(:process_chunk)
    end
  end

  describe 'a listener run' do
    before do
      allow(described_class).to receive(:new).and_call_original
      allow(Orchestration::Connection).to receive(:configure!)
      allow(Orchestration::StackStatus).to receive(:refresh!)
      allow(listener).to receive(:sleep)
    end

    it 'refreshes the stack status when it reconnects' do
      allow(listener).to receive(:stream_events)

      expect(listener.send(:listen_once, true)).to be(false)
      expect(Orchestration::StackStatus).to have_received(:refresh!)
    end

    # A socket error is the normal end of a stream (daemon restart); the next
    # pass reconnects, and only a stopped listener gives up.
    it 'asks for a reconnect after a socket error' do
      allow(listener).to receive(:stream_events).and_raise(Excon::Error::Socket.new(StandardError.new('gone')))
      listener.send(:instance_variable_get, :@running).make_true

      expect(listener.send(:listen_once, false)).to be(true)
    end

    it 'gives up once the listener has been stopped' do
      allow(listener).to receive(:stream_events).and_raise(StandardError, 'boom')

      expect(listener.send(:listen_once, false)).to be(false)
    end

    it 'joins the threads of a listener that was never started' do
      expect { listener.stop }.not_to raise_error
      expect(listener.send(:threads_alive?)).to be_falsey
    end

    # The scheduler thread ticks on an interval and reconciles its subscribers
    # every RECONCILE_TICKS ticks.
    it 'ticks and reconciles until it is stopped' do
      stub_const("#{described_class}::RECONCILE_TICKS", 2)
      allow(listener).to receive(:initial_refresh)
      allow(listener).to receive(:reconcile_subscribers)
      ticks = 0
      allow(listener).to receive(:run_scheduler_tick) do
        ticks += 1
        listener.mark_stopped! if ticks == 2
      end
      listener.send(:instance_variable_get, :@running).make_true

      listener.send(:scheduler_loop)

      expect(ticks).to eq(2)
      expect(listener).to have_received(:reconcile_subscribers).once
    end

    # The loop keeps reconnecting until the listener is stopped, and logs that
    # it ended — the last line of the thread.
    it 'runs until the listener is stopped' do
      running = listener.send(:instance_variable_get, :@running)
      running.make_true
      passes = 0
      allow(listener).to receive(:listen_once) do
        passes += 1
        running.make_false if passes == 2
        true
      end

      listener.send(:listen_loop)

      expect(passes).to eq(2)
    end

    # Deliberately without `start`: a listener whose threads outlive the
    # example takes its work into the next one (see spec/support).
    it 'stops a listener that is marked running' do
      listener.send(:instance_variable_get, :@running).make_true

      listener.stop

      expect(listener).not_to be_running
    end

    # The listener thread blocks on the Docker event stream and never observes
    # the running flag, so joining it could only time out.
    it 'force-kills a thread that cannot be joined' do
      thread = Thread.new { sleep 5 } # rubocop:disable ThreadSafety/NewThread
      thread.name = 'docker-events-test'

      listener.send(:kill_thread, thread)
      thread.join(1)

      expect(thread).not_to be_alive
    end
  end

  describe 'the scheduler thread' do
    before do
      allow(described_class).to receive(:new).and_call_original
      allow(Orchestration::StackStatus).to receive(:refresh!)
      allow(Orchestration::OrphanedServices).to receive(:prune!)
    end

    # Docker being unreachable at boot must not take the scheduler thread
    # down — the next tick tries again.
    it 'survives a failing initial refresh' do
      allow(Orchestration::StackStatus).to receive(:refresh!).and_raise(StandardError, 'no docker')

      expect { listener.send(:initial_refresh) }.not_to raise_error
    end

    it 'survives a failing tick' do
      allow(listener).to receive(:process_pending_broadcasts).and_raise(StandardError, 'boom')

      expect { listener.send(:run_scheduler_tick) }.not_to raise_error
    end

    # Browser tabs can go away without a disconnect reaching HELIOS; the
    # listener then has no one left to talk to and stops itself. The count is
    # set directly — `subscriber_connected` would start a second listener.
    it 'stops itself once every connection is gone' do
      stub_subscribed_connections([])

      listener.send(:reconcile_subscribers)

      expect(described_class).to have_received(:stop_abandoned).with(listener)
    end

    it 'keeps running while connections remain' do
      stub_subscribed_connections([instance_double(ActionCable::Connection::Base)])

      listener.send(:reconcile_subscribers)

      expect(described_class).not_to have_received(:stop_abandoned)
    end

    # The count is set directly: `subscriber_connected` would start a second,
    # real listener whose threads outlive the example.
    def stub_subscribed_connections(connections)
      DOCKER_EVENTS_STORAGE[:subscriber_count] = 1
      allow(ActionCable.server).to receive(:connections).and_return(connections)
      allow(described_class).to receive(:stop_abandoned)
    end

    it 'survives a failing reconciliation' do
      allow(ActionCable.server).to receive(:connections).and_raise(StandardError, 'boom')

      expect { listener.send(:reconcile_subscribers) }.not_to raise_error
    end
  end

  # A HELIOS operation (backup, restore, stack start) changes several services
  # at once, so the whole status bar is refreshed instead of one row.
  describe 'a HELIOS operation event' do
    let(:event) do
      instance_double(Orchestration::Event, relevant?: false, helios_operation?: true,
                                            service_name: nil, action: 'helios')
    end

    before do
      allow(described_class).to receive(:new).and_call_original
      allow(Orchestration::StackStatus).to receive(:refresh!)
      allow(Orchestration::HeliosOperationBroadcaster).to receive(:broadcast!)
    end

    it 'refreshes the whole stack status' do
      listener.send(:process_event, event)

      expect(Orchestration::StackStatus).to have_received(:refresh!)
      expect(Orchestration::HeliosOperationBroadcaster).to have_received(:broadcast!)
        .with(locale: described_class.locale)
    end
  end

  # A broadcast can fail because the container is mid-transition; retrying with
  # a growing delay covers that without hammering the socket.
  describe 'a failing broadcast' do
    let(:broadcaster) { instance_double(Orchestration::ServiceBroadcaster) }

    before do
      allow(described_class).to receive(:new).and_call_original
      allow(Orchestration::ServiceBroadcaster).to receive(:new).and_return(broadcaster)
      allow(broadcaster).to receive(:broadcast).and_return(false)
      allow(Orchestration::OrphanedServices).to receive(:prune!)
    end

    it 'retries with a growing delay and gives up after the last attempt' do
      listener.send(:schedule_broadcast, 'db')

      # 1s, 2s, 4s — each retry only falls due after its own delay.
      travel(2.seconds) { listener.send(:run_scheduler_tick) }
      travel(4.seconds) { listener.send(:run_scheduler_tick) }
      travel(8.seconds) { listener.send(:run_scheduler_tick) }
      travel(16.seconds) { listener.send(:run_scheduler_tick) }
      travel(32.seconds) { listener.send(:run_scheduler_tick) }

      expect(broadcaster).to have_received(:broadcast).exactly(4).times
    end
  end

  # Before this, a leftover container whose service compose.yaml no longer
  # knows produced three failed broadcasts per event, and the next event
  # started over. The broadcaster now reports it and the sweep removes it.
  describe 'an event for a service compose.yaml no longer knows' do
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
