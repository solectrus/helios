module Import
  class ConfigurationImporter
    # Resolves bind-mount host paths for sections that persist data
    # (postgresql, influxdb, redis, ingest, reverse_proxy). Inline `volumes:`
    # bindings take precedence over the legacy `*_VOLUME_PATH` env var because
    # the inline form is more common in real-world installs and absorbs
    # `${VAR}` interpolation that the env var alone can't express.
    class VolumeResolver
      # Per-section bind-mount detection metadata. `container_target` matches
      # against the user's inline `volumes:` block when the host source isn't
      # exposed via `*_VOLUME_PATH`. It may be an array: Postgres exposes a
      # different image `VOLUME` per major version (`postgres:17` and older
      # mount `/var/lib/postgresql/data`, `postgres:18`+ mount the parent
      # `/var/lib/postgresql`), so both are accepted on import. The host
      # source is recorded verbatim; the export side re-emits whichever
      # target matches the (preserved) image version.
      VOLUME_PATH_ENVS = {
        'postgresql' => { env_key: 'DB_VOLUME_PATH', default_dir: 'postgresql',
                          container_target: ['/var/lib/postgresql', '/var/lib/postgresql/data'] },
        'influxdb' => { env_key: 'INFLUX_VOLUME_PATH', default_dir: 'influxdb',
                        container_target: '/var/lib/influxdb2' },
        'redis' => { env_key: 'REDIS_VOLUME_PATH', default_dir: 'redis',
                     container_target: '/data' },
        'ingest' => { env_key: 'INGEST_VOLUME_PATH', default_dir: 'ingest',
                      container_target: '/app/data' },
        'reverse_proxy' => { env_key: 'TRAEFIK_VOLUME_PATH', default_dir: 'traefik',
                             container_target: '/letsencrypt', service_name: 'traefik' },
      }.freeze

      INTERPOLATION_RE = /\$\{([A-Z_][A-Z0-9_]*)\}/
      INTERPOLATION_MAX_DEPTH = 10

      # Docker named-volume name: starts with alphanumeric, no slashes — the
      # only form Compose accepts on the source side that isn't a host path.
      NAMED_VOLUME_RE = /\A[a-zA-Z0-9][a-zA-Z0-9_.-]*\z/

      def initialize(reader)
        @reader = reader
      end

      # Preserve absolute host paths (e.g. Synology `/volume1/...`, or
      # `${BASE_DIR}/influxdb/data` resolved against .env) and Docker named
      # volume names (e.g. `influxdb-data`) so the stack keeps reusing the
      # same storage after import. Relative bind mounts and absolute paths
      # that resolve to the default bind mount next to compose.yaml are
      # dropped — they match HELIOS's default anyway.
      def path_data(section)
        mapping = VOLUME_PATH_ENVS.fetch(section)
        value = inline_volume_source(section, mapping) ||
                resolve_interpolation(@reader.raw_env[mapping[:env_key]])
        return {} unless meaningful_volume_value?(value, mapping)

        { 'volume_path' => value }
      end

      def meaningful_volume_value?(value, mapping)
        return false if value.blank?
        return value.match?(NAMED_VOLUME_RE) unless value.start_with?('/')

        File.expand_path(value) != File.expand_path(mapping[:default_dir], @reader.stack_dir)
      end

      # Recursive `${VAR}` substitution against raw .env, with cycle protection.
      # Real-world stacks chain references (e.g. `HOST_DUMP=${BASE_DIR}/db_dumps`),
      # so a single-pass gsub isn't enough.
      def resolve_interpolation(value, depth = 0, seen = Set.new)
        return value if depth > INTERPOLATION_MAX_DEPTH || value.nil?

        value.to_s.gsub(INTERPOLATION_RE) do
          var = ::Regexp.last_match(1)
          next '' if seen.include?(var)

          raw = @reader.raw_env[var]
          raw.nil? ? '' : resolve_interpolation(raw, depth + 1, seen + [var])
        end
      end

      private

      # First inline `volumes:` source matching any of the section's container
      # targets. Postgres lists two (see VOLUME_PATH_ENVS) so a stack importing
      # either the `postgres:17`-style `/var/lib/postgresql/data` mount or the
      # `postgres:18`-style `/var/lib/postgresql` mount resolves the same way.
      def inline_volume_source(section, mapping)
        service = mapping[:service_name] || section
        Array(mapping[:container_target]).lazy.filter_map do |target|
          resolved_volume_source(service, target)
        end.first
      end

      # Resolved source of the volume entry whose container target matches
      # `target` — either an absolute host path or a Docker named-volume
      # name. Returns nil when no entry matches or the source is a relative
      # bind mount (which HELIOS treats as the default and drops).
      def resolved_volume_source(service_name, target)
        raw_volumes = Array(raw_service_config(service_name)&.dig('volumes'))
        raw_source = raw_volumes.lazy.filter_map { |entry| volume_source_for_target(entry, target) }.first
        resolved = resolve_interpolation(raw_source).to_s.chomp('/')
        return nil if resolved.blank?

        resolved if resolved.start_with?('/') || resolved.match?(NAMED_VOLUME_RE)
      end

      # Image-prefix alias fallback so installs that renamed the service (e.g.
      # `postgres:` instead of `postgresql:`) still resolve.
      def raw_service_config(canonical_name)
        raw = @reader.raw_compose['services'] || {}
        return raw[canonical_name] if raw.key?(canonical_name)

        prefixes = StackReader::SERVICE_IMAGE_PREFIXES[canonical_name]
        return nil unless prefixes

        raw.each_value.find { |cfg| cfg.is_a?(Hash) && StackReader.image_matches?(cfg['image'], prefixes) }
      end

      def volume_source_for_target(entry, target)
        return nil unless entry.is_a?(String)

        source, mounted_target, = entry.split(':', 3)
        return nil unless mounted_target

        resolved = resolve_interpolation(mounted_target).to_s.chomp('/')
        source if resolved == target.to_s.chomp('/')
      end
    end
  end
end
