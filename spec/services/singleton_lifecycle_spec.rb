RSpec.describe SingletonLifecycle do
  # A minimal singleton worker: the storage map lives in the example, the way
  # the real ones live in an initializer.
  let(:storage) { Concurrent::Map.new }
  let(:worker_class) do
    map = storage
    stub_const(
      'SingletonLifecycleTestWorker',
      Class.new do
        extend SingletonLifecycle

        define_singleton_method(:storage) { map }

        attr_reader :started

        def start = @started = true
        def stop = @started = false
        def running? = @started == true
      end,
    )
  end

  after { worker_class.stop }

  it 'keeps one live instance across repeated starts' do
    worker_class.start
    first = worker_class.send(:instance)
    worker_class.start

    expect(worker_class).to be_running
    expect(worker_class.send(:instance)).to be(first)
  end

  # A restart has to hand out a fresh instance: the old one carries the state
  # (threads, counters) the restart is meant to drop.
  it 'replaces the instance on restart' do
    worker_class.start
    first = worker_class.send(:instance)

    worker_class.restart

    expect(worker_class.send(:instance)).not_to be(first)
    expect(first.started).to be(false)
    expect(worker_class).to be_running
  end

  it 'stops and forgets the instance' do
    worker_class.start

    worker_class.stop

    expect(worker_class.send(:instance)).to be_nil
    expect(worker_class).not_to be_running
  end

  it 'demands a storage map from the class that extends it' do
    klass = Class.new { extend SingletonLifecycle }

    expect { klass.start }.to raise_error(NotImplementedError, /must define `storage`/)
  end
end
