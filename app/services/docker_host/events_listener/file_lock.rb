module DockerHost
  class EventsListener
    # File-based lock to ensure only one listener runs across all processes
    module FileLock
      LOCK_FILE = 'tmp/docker_events.lock'.freeze

      def try_acquire_file_lock # rubocop:disable Naming/PredicateMethod
        file = Rails.root.join(LOCK_FILE).open(File::RDWR | File::CREAT)
        if file.flock(File::LOCK_EX | File::LOCK_NB)
          storage[:lock_file] = file
          true
        else
          file.close
          false
        end
      end

      def release_file_lock
        return unless storage[:lock_file]

        storage[:lock_file].flock(File::LOCK_UN)
        storage[:lock_file].close
        storage[:lock_file] = nil
      end
    end
  end
end
