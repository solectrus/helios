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
      # exposed via `*_VOLUME_PATH`. Postgres opts in to a PGDATA-subpath
      # fallback (`<host>/data:/var/lib/postgresql/data`).
      VOLUME_PATH_ENVS = {
        'postgresql' => { env_key: 'DB_VOLUME_PATH', default_dir: 'postgresql',
                          container_target: '/var/lib/postgresql', pgdata_fallback: true },
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

      def initialize(reader)
        @reader = reader
      end

      # Preserve absolute host paths (e.g. Synology `/volume1/...`, or
      # `${BASE_DIR}/influxdb/data` resolved against .env) so the stack keeps
      # pointing at the existing data directory after import. Relative values
      # and absolute paths that resolve to the default bind mount next to
      # compose.yaml are dropped — they match HELIOS's default anyway.
      def path_data(section)
        mapping = VOLUME_PATH_ENVS.fetch(section)
        value = inline_volume_source(section, mapping) ||
                (mapping[:pgdata_fallback] && pgdata_subpath_source) ||
                resolve_interpolation(@reader.raw_env[mapping[:env_key]])
        return {} unless value&.start_with?('/')
        return {} if File.expand_path(value) == File.expand_path(mapping[:default_dir], @reader.stack_dir)

        { 'volume_path' => value }
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

      def inline_volume_source(section, mapping)
        target = mapping[:container_target]
        target && resolved_volume_source(mapping[:service_name] || section, target)
      end

      # Resolved absolute host path of the volume entry whose container target
      # matches `target`, or nil if no entry matches or the source is relative.
      def resolved_volume_source(service_name, target)
        raw_volumes = Array(raw_service_config(service_name)&.dig('volumes'))
        raw_source = raw_volumes.lazy.filter_map { |entry| volume_source_for_target(entry, target) }.first
        resolved = resolve_interpolation(raw_source)
        resolved if resolved&.start_with?('/')
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

      # Stacks that bind-mount the PGDATA subpath
      # (`<host>/data:/var/lib/postgresql/data`) instead of the parent dir.
      # Only safe to transform if the host source ends in `/data` — strip it
      # so HELIOS's parent-mount strategy (`<host>:/var/lib/postgresql`) lines
      # up; PGDATA stays at `/var/lib/postgresql/data` via the preserved env
      # var, so the container still finds the same bytes on disk.
      def pgdata_subpath_source
        pgdata = resolve_interpolation(@reader.raw_env['PGDATA']).presence ||
                 '/var/lib/postgresql/data'
        resolved = resolved_volume_source('postgresql', pgdata)
        return nil unless resolved

        parent = resolved.sub(%r{/data/?\z}, '')
        parent unless parent == resolved
      end
    end
  end
end
