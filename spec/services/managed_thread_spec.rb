RSpec.describe ManagedThread do
  # A minimal concrete subclass: ticks a counter every 10ms. stub_const gives
  # the anonymous class a real name, which ManagedThread needs for both the
  # thread name and the Loggable tag.
  let(:worker_class) do
    stub_const(
      'ManagedThreadTestWorker',
      Class.new(ManagedThread) do
        def initialize
          super
          @ticks = Concurrent::AtomicFixnum.new(0)
        end

        def ticks = @ticks.value

        private

        def interval = 0.01

        def run_once = @ticks.increment
      end,
    )
  end

  let(:worker) { worker_class.new }

  after { worker.stop }

  # Spin until the block turns truthy (or we give up), so assertions never race
  # the background thread without resorting to a fixed sleep.
  def wait_for(timeout: 2)
    (timeout / 0.02).to_i.times do
      break if yield

      sleep 0.02
    end
  end

  it 'assigns a short hex id' do
    expect(worker.id).to match(/\A[0-9a-f]{8}\z/)
  end

  it 'is not running before it starts' do
    expect(worker.running?).to be(false)
  end

  describe '#start' do
    it 'runs the loop and reports running' do
      worker.start

      expect(worker.running?).to be(true)
      wait_for { worker.ticks.positive? }
      expect(worker.ticks).to be_positive
    end

    it 'names the thread after the class and id' do
      worker.start

      expect(worker.send(:thread).name).to eq("managed-thread-test-worker-#{worker.id}")
    end
  end

  describe '#stop' do
    it 'stops the loop and reports not running' do
      worker.start
      wait_for { worker.ticks.positive? }

      worker.stop

      expect(worker.running?).to be(false)
    end

    it 'halts further ticks' do
      worker.start
      wait_for { worker.ticks.positive? }
      worker.stop

      ticks_after_stop = worker.ticks
      sleep 0.05

      expect(worker.ticks).to eq(ticks_after_stop)
    end

    it 'is a no-op when never started' do
      expect { worker.stop }.not_to raise_error
      expect(worker.running?).to be(false)
    end

    it 'force-kills a thread that does not join in time' do
      worker.start
      # Simulate the join timing out, forcing the kill fallback.
      allow(worker.send(:thread)).to receive(:join).and_return(nil)

      worker.stop

      expect(worker.running?).to be(false)
    end
  end

  describe 'abstract hooks' do
    it 'requires subclasses to define interval' do
      expect { described_class.new.send(:interval) }
        .to raise_error(NotImplementedError, /must define `interval`/)
    end

    it 'requires subclasses to define run_once' do
      expect { described_class.new.send(:run_once) }
        .to raise_error(NotImplementedError, /must define `run_once`/)
    end
  end
end
