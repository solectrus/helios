module Orchestration
  # Determines which services need a restart by comparing
  # the current Docker Compose config hashes (from compose.yaml + .env)
  # against the hashes stored at the time of the last Helios-initiated
  # deployment.
  #
  # By comparing two runs of the same Helios-internal Docker Compose
  # binary (instead of comparing against container labels set by the
  # host's Docker Compose), this avoids false positives caused by
  # Docker Compose version mismatches between the Helios container
  # and the host system.
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

    # Invalidate the expected config hashes and the derived affected-services
    # cache (stale config hashes make the affected-services cache meaningless).
    def self.invalidate_config_hashes
      Rails.cache.delete(CONFIG_HASH_CACHE_KEY)
      Rails.cache.delete(AFFECTED_CACHE_KEY)
    end

    # Persist the current expected config hashes as the "deployed" baseline.
    # Called after successful Helios-initiated deployments so that subsequent
    # comparisons know which config was last applied.
    def self.store_deployed_hashes!
      hashes = Runner.config_hashes.except(Runner::SELF_SERVICE)
      Rails.cache.write(CONFIG_HASH_CACHE_KEY, hashes)
      ::File.write(deployed_hashes_path, hashes.to_json)
      Rails.cache.delete(AFFECTED_CACHE_KEY)
    rescue StandardError => e
      Rails.logger.error(
        "AffectedServices: failed to store deployed hashes: #{e.message}",
      )
    end

    # Update the deployed hash for a single service when its container
    # is recreated externally (e.g. via Docker CLI). This ensures the
    # "restart required" marker disappears after a manual restart that
    # applies the current compose.yaml config.
    def self.update_deployed_hash!(service_name)
      deployed = load_deployed_hashes_file
      return if deployed.empty?

      expected = Runner.config_hashes.except(Runner::SELF_SERVICE)
      hash = expected[service_name]
      return unless hash

      # Drop entries for services that no longer exist in compose.yaml
      pruned = deployed.slice(*expected.keys)
      pruned[service_name] = hash
      return if pruned == deployed

      ::File.write(deployed_hashes_path, pruned.to_json)
      Rails.cache.delete(CONFIG_HASH_CACHE_KEY)
      Rails.cache.delete(AFFECTED_CACHE_KEY)
    rescue StandardError => e
      Rails.logger.error(
        "AffectedServices: failed to update deployed hash for #{service_name}: #{e.message}",
      )
    end

    def self.load_deployed_hashes_file
      JSON.parse(::File.read(deployed_hashes_path))
    rescue Errno::ENOENT, JSON::ParserError
      {}
    end

    def self.deployed_hashes_path
      Rails.root.join('storage/deployed_config_hashes.json')
    end

    def compute
      expected = expected_hashes
      return [] if expected.empty?

      deployed = load_deployed_hashes
      return seed_deployed_hashes(expected) if deployed.empty?

      compare_hashes(expected, deployed)
    rescue Runner::CommandError, ConnectionError => e
      Rails.logger.error("AffectedServices: #{e.message}")
      []
    end

    private

    def seed_deployed_hashes(expected)
      write_deployed_hashes(expected)
      []
    end

    def compare_hashes(expected, deployed)
      containers = Container.all.index_by(&:service_name)

      expected.filter_map do |name, hash|
        container = containers[name]
        next if container.nil?
        next if deployed[name] == hash

        name
      end
    end

    def expected_hashes
      Rails
        .cache
        .fetch(CONFIG_HASH_CACHE_KEY) { Runner.config_hashes.except(Runner::SELF_SERVICE) }
    end

    def load_deployed_hashes
      self.class.load_deployed_hashes_file
    end

    def write_deployed_hashes(hashes)
      ::File.write(self.class.deployed_hashes_path, hashes.to_json)
    rescue StandardError => e
      Rails.logger.error(
        "AffectedServices: failed to store deployed hashes: #{e.message}",
      )
    end
  end
end
