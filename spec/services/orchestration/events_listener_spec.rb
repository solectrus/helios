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
    it 'stops the instance gracefully and clears it' do
      described_class.start
      described_class.stop

      aggregate_failures do
        expect(fake_instance).to have_received(:stop).with(graceful: true)
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
        expect(fake_instance).to have_received(:stop).with(graceful: false)
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
        expect(fake_instance).to have_received(:stop).with(graceful: false)
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
end
