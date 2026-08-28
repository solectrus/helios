# Base class for a process-wide singleton that runs exactly one background
# thread, ticking a `run_once` body every `interval` seconds. The thread is
# named after the subclass and shut down with a wakeup/join/kill sequence.
#
# Subclasses implement:
#   - self.storage  — the Concurrent::Map for singleton state (see SingletonLifecycle)
#   - self.logger   — where lifecycle and tick messages go
#   - #interval     — seconds between ticks
#   - #run_once     — one iteration of work
#
# The class-level singleton management (start/stop/restart/running?) is mixed in
# from SingletonLifecycle, which is also shared with classes that cannot inherit
# from ManagedThread (e.g. Orchestration::EventsListener with its two threads).
class ManagedThread
  extend SingletonLifecycle
  include Loggable
  extend Loggable

  attr_reader :id

  def initialize
    @id = SecureRandom.hex(4)
    @running = Concurrent::AtomicBoolean.new(false)
  end

  def start
    @running.make_true

    # rubocop:disable-next ThreadSafety/NewThread -- background thread is intentional
    self.thread = Thread.new { run_loop }
    thread.name = thread_name
    logger.info("Started (#{thread.name})")
  end

  def stop
    return unless @running.true? || thread&.alive?

    logger.info("Stopping (#{id})")
    @running.make_false
    terminate_thread
    logger.info("Stopped (#{id})")
  end

  def running?
    @running.true? && thread&.alive?
  end

  private

  attr_accessor :thread

  def thread_name
    "#{self.class.name.demodulize.underscore.dasherize}-#{id}"
  end

  def terminate_thread
    thread&.wakeup rescue nil # rubocop:disable Style/RescueModifier
    thread&.join(2)
    thread.kill if thread&.alive?
  end

  def run_loop
    while @running.true?
      sleep interval
      break unless @running.true?

      run_once
    end
  end

  # Seconds between ticks. Subclass responsibility.
  def interval
    raise NotImplementedError, "#{self.class} must define `interval`"
  end

  # One iteration of work. Subclass responsibility.
  def run_once
    raise NotImplementedError, "#{self.class} must define `run_once`"
  end
end
