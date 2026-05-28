module Orchestration
  # Clears the Redis cache of a running container.
  #
  # SOLECTRUS keeps a Redis-backed cache of data derived from PostgreSQL.
  # After a database swap or restore that cache can hold stale entries that
  # no longer match the database — flushing it forces a clean rebuild.
  #
  # FLUSHALL empties the in-memory dataset; the following SAVE persists the
  # now-empty state to dump.rdb, so a later container restart cannot reload
  # the stale data from disk.
  class RedisCacheFlush
    def self.call(container)
      new(container).call
    end

    def initialize(container)
      @container = container
    end

    def call
      return false unless container&.running?

      redis_cli('FLUSHALL') && redis_cli('SAVE')
    end

    private

    attr_reader :container

    def redis_cli(*command)
      Rails.logger.info(
        "[#{self.class.name}] docker exec #{container.name} redis-cli #{command.join(' ')}",
      )
      _stdout, _stderr, exit_code = container.exec(['redis-cli', *command])
      exit_code&.zero? || false
    rescue Docker::Error::DockerError, Excon::Error => e
      Rails.logger.warn("[#{self.class.name}] failed: #{e.class}: #{e.message}")
      false
    end
  end
end
