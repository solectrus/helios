# Class-level lifecycle for a process-wide singleton background worker:
# start/stop/restart/running? plus the mutex-guarded accessors that keep at
# most one live instance alive at a time.
#
# `extend` this into a class. The class must provide `storage` — a
# Concurrent::Map living outside the autoload paths (defined in an initializer)
# so the singleton state survives code reloading in development.
#
# Shared by ManagedThread (single-thread workers like BackupScheduler) and by
# Orchestration::EventsListener, which runs its own multi-thread instance but
# reuses this exact singleton wiring. A class can override restart/stop_instance
# (EventsListener adds a restart cooldown) — its own definitions take
# precedence over the ones mixed in here.
module SingletonLifecycle
  def start
    class_mutex.synchronize { start_instance }
  end

  def stop
    class_mutex.synchronize { stop_instance }
  end

  def restart
    class_mutex.synchronize do
      stop_instance
      start_instance
    end
  end

  def running?
    instance&.running?
  end

  def class_mutex
    storage[:mutex] ||= Mutex.new
  end

  private

  # The Concurrent::Map holding the singleton's :mutex and :instance.
  def storage
    raise NotImplementedError, "#{self} must define `storage`"
  end

  def start_instance
    return if instance&.running?

    instance&.stop
    new_instance = new
    new_instance.start
    self.instance = new_instance
  end

  def stop_instance
    return unless instance

    instance.stop
    self.instance = nil
  end

  def instance
    storage[:instance]
  end

  def instance=(value)
    storage[:instance] = value
  end
end
