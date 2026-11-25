require 'digest'

module Orchestration
  # Remembers what each deployed service looked like, so a pending restart
  # can name its reason. AffectedServices compares opaque config hashes and
  # knows only *that* a service changed; this compares the parts.
  #
  # Per service it stores every environment variable as a digest of its
  # value (no secret lands in the file in clear text) and one digest per
  # other part of the definition (image, healthcheck, volumes, ...). Each
  # entry carries the config hash it was taken from: an entry whose hash no
  # longer matches the deployed one is stale and yields no reason rather
  # than a wrong one.
  class ConfigFingerprints
    extend Loggable

    CACHE_KEY = 'orchestration/config_fingerprints'.freeze

    # Variable names that were added, removed or given another value, and
    # the other parts of the service definition that changed.
    Change = Data.define(:added, :removed, :changed, :parts) do
      def empty?
        [added, removed, changed, parts].all?(&:empty?)
      end
    end

    class << self
      # Takes a fingerprint of every service whose current config is the
      # deployed one and whose stored fingerprint is missing or stale. Runs
      # `docker compose config` only when there is such a service.
      def sync!(deployed, current)
        stored = load_file
        names = deployed.keys.select { |name| refresh?(stored[name], deployed[name], current[name]) }
        return if names.empty?

        stored.merge!(fresh_entries(names, deployed))
        write_file!(stored.slice(*deployed.keys))
      rescue Runner::CommandError, ConnectionError, JSON::ParserError => e
        logger.error("failed to store config fingerprints: #{e.message}")
      end

      # What differs between the deployed and the current config of a
      # service, or nil when the deployed state is unknown.
      def change(name, deployed_hash)
        before = load_file[name]
        return unless before && before['hash'] == deployed_hash

        after = current_fingerprints[name]
        return unless after

        result = diff(before, after)
        result unless result.empty?
      rescue Runner::CommandError, ConnectionError, JSON::ParserError => e
        logger.error("failed to compare config fingerprints: #{e.message}")
        nil
      end

      def invalidate_cache
        Rails.cache.delete(CACHE_KEY)
      end

      def path
        File.join(Rails.configuration.data_path, 'helios', 'deployed_config_fingerprints.json')
      end

      def load_file
        JSON.parse(::File.read(path))
      rescue Errno::ENOENT, JSON::ParserError
        {}
      end

      private

      # Reads compose afresh: at boot, a cached result would outlive the
      # rewrite of compose.yaml that follows.
      def fresh_entries(names, deployed)
        fingerprints = compose_fingerprints.slice(*names)
        fingerprints.to_h { |name, fingerprint| [name, fingerprint.merge('hash' => deployed[name])] }
      end

      def refresh?(entry, deployed_hash, current_hash)
        deployed_hash == current_hash && entry&.dig('hash') != deployed_hash
      end

      def current_fingerprints
        Rails.cache.fetch(CACHE_KEY) { compose_fingerprints }
      end

      def compose_fingerprints
        Runner.config_services.transform_values { |service| fingerprint(service) }
      end

      def fingerprint(service)
        {
          'environment' => (service['environment'] || {}).transform_values { |value| digest(value) },
          'parts' => service.except('environment').transform_values { |part| digest(canonical(part).to_json) },
        }
      end

      def canonical(value)
        case value
        when Hash then value.sort.to_h { |key, item| [key, canonical(item)] }
        when Array then value.map { |item| canonical(item) }
        else value
        end
      end

      def diff(before, after)
        Change.new(
          **variable_changes(before['environment'] || {}, after['environment'] || {}),
          parts: changed_keys(before['parts'] || {}, after['parts'] || {}),
        )
      end

      def changed_keys(old_parts, new_parts)
        (old_parts.keys | new_parts.keys).reject { |key| old_parts[key] == new_parts[key] }.sort
      end

      def variable_changes(old_env, new_env)
        {
          added: (new_env.keys - old_env.keys).sort,
          removed: (old_env.keys - new_env.keys).sort,
          changed: (old_env.keys & new_env.keys).reject { |key| old_env[key] == new_env[key] }.sort,
        }
      end

      def digest(value)
        Digest::SHA256.hexdigest(value.to_s)
      end

      def write_file!(data)
        FileUtils.mkdir_p(::File.dirname(path))
        ::File.write(path, data.to_json)
      end
    end
  end
end
