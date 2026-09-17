module Import
  class ConfigurationImporter
    module Helpers
      # Maps device type to the field name that holds the data source identifier
      DATA_SOURCE_FIELDS = {
        'inverter' => 'battery_vendor',
        'wallbox' => 'wallbox_vendor',
        'heatpump' => 'heatpump_access',
      }.freeze

      # All fields on a device that can carry its source identifier — the
      # generic 'data_source' slot plus the type-specific slots from
      # DATA_SOURCE_FIELDS.
      SOURCE_FIELDS = (['data_source'] + DATA_SOURCE_FIELDS.values).freeze

      # InfluxDB power fields the shelly-collector writes (per
      # github.com/solectrus/shelly-collector). 1- and 2-channel devices fill
      # only `power`; 3-phase devices (Pro 3EM, Plus 3EM) additionally fill
      # `power_a`/`power_b`/`power_c` so a single Shelly can feed multiple
      # HELIOS sensors from one measurement.
      SHELLY_POWER_FIELDS = %w[power power_a power_b power_c].freeze

      # Wildcard bind addresses are equivalent to "no explicit bind" — HELIOS
      # already defaults to all interfaces, so they name no host IP.
      WILDCARD_IPS = %w[0.0.0.0 ::].freeze

      private

      # --- Port mappings ---
      #
      # `docker compose config --format json` normalizes short-form ports to
      # long-form hashes (target/published/protocol). Every reader below
      # handles both, so a raw-YAML fallback path stays compatible too.

      # Container side of a port mapping, protocol suffix stripped.
      def container_port(entry)
        return entry['target'].to_i if entry.is_a?(Hash)

        entry.to_s.split('/').first.to_s.split(':').last.to_i
      end

      # Host side of a port mapping, nil where the mapping publishes none
      # (a bare `1883`). A bind IP is not part of it, so a caller that cares
      # which interface the port sits on has to read #host_ip as well.
      def published_host_port(entry)
        return entry['published'].presence&.to_s if entry.is_a?(Hash)

        parts = entry.to_s.split('/').first.to_s.split(':')
        parts[-2] if parts.size >= 2
      end

      # The single host interface a port mapping binds to. Nil for a wildcard
      # bind and for a mapping that names no interface at all: both publish on
      # every interface and carry no information HELIOS needs to persist.
      def host_ip(entry)
        ip =
          if entry.is_a?(Hash)
            entry['host_ip']
          else
            parts = entry.to_s.split(':', 3)
            parts.first if parts.size == 3
          end

        ip if ip.present? && WILDCARD_IPS.exclude?(ip)
      end

      # Environment of a specific service (memoized per service name).
      #
      # `docker compose config` re-emits literal `$` as `$$` in its output so
      # the JSON could be re-fed to compose without re-interpreting variable
      # references. We undo that here to recover the actual runtime string the
      # container would see (e.g. JSONPath `$.foo` instead of `$$.foo`).
      def service_env(name)
        @service_envs ||= {}
        @service_envs[name] ||= unescape_compose_dollars(
          @reader.service(name)&.dig('environment') || {},
        )
      end

      def unescape_compose_dollars(env)
        env.transform_values { |v| v.is_a?(String) ? v.gsub('$$', '$') : v }
      end

      def csv_split(value)
        value.to_s.split(',').map(&:strip)
      end

      # First non-blank value across env keys, preferring earlier ones. Real-world
      # stacks routinely use non-canonical names (POSTGRES_ADMIN_PASSWORD,
      # DOCKER_INFLUXDB_INIT_*, INFLUX_ADMIN_TOKEN, ...) — without the fallback
      # the importer would persist nil and ensure_defaults! would generate a
      # fresh random secret on every export, breaking round-trip stability.
      #
      # `inline:` adds a service-scoped fallback for stacks that put values
      # directly in `environment:` and ship no .env (legitimate compose pattern).
      # Scoped — not global — to avoid picking up role-bound `INFLUX_TOKEN=${INFLUX_TOKEN_READ}`
      # from a collector when looking up an admin token.
      def env_first(*keys, inline: nil)
        inline_env = inline ? service_env(inline) : {}
        keys.lazy.filter_map { |k| inline_env[k].presence || @reader.raw_env[k].presence }.first
      end

      def image_data_for(service_name)
        image = Compose.normalize_image(@reader.service(service_name)&.dig('image'))
        { 'image' => image }.compact
      end

      def find_sensor_for_candidate(sensors, candidate)
        sensors.find { |_, value| value == candidate }&.first
      end

      # Measurement half of a sensor's `measurement:field` mapping, by name.
      def sensor_measurement(sensor_name)
        @sensors_data[sensor_name].to_s.split(':', 2).first
      end
    end
  end
end
