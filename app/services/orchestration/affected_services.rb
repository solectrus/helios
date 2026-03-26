module Orchestration
  # Determines which services need a restart by comparing
  # Docker Compose config hashes (from compose.yaml + .env)
  # against the config hashes stored on running containers.
  #
  # Results are cached briefly to avoid repeated subprocess calls
  # within the same render cycle.
  class AffectedServices
    CACHE_TTL = 5.seconds
    CONFIG_HASH_CACHE_KEY = 'orchestration/config_hashes'.freeze
    AFFECTED_CACHE_KEY = 'orchestration/affected_services'.freeze

    def self.compute
      Rails
        .cache
        .fetch(AFFECTED_CACHE_KEY, expires_in: CACHE_TTL) { new.compute }
    end

    def self.invalidate_cache
      Rails.cache.delete(AFFECTED_CACHE_KEY)
    end

    # Invalidate the expected config hashes (only needed on config change)
    def self.invalidate_config_hashes
      Rails.cache.delete(CONFIG_HASH_CACHE_KEY)
    end

    def compute
      expected = expected_hashes
      return [] if expected.empty?

      containers = Container.all.index_by(&:service_name)

      expected.filter_map do |name, hash|
        container = containers[name]
        next if container.nil?
        next if container.config_hash == hash

        name
      end
    rescue Runner::CommandError, ConnectionError => e
      Rails.logger.error("AffectedServices: #{e.message}")
      []
    end

    private

    def expected_hashes
      Rails
        .cache
        .fetch(CONFIG_HASH_CACHE_KEY) { Runner.config_hashes.except('helios') }
    end
  end
end
