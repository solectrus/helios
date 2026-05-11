module Import
  class ConfigurationImporter
    class InfluxdbExtractor
      include Helpers

      # Container port the InfluxDB UI always listens on.
      INFLUXDB_CONTAINER_PORT = 8086

      def initialize(reader, volume_resolver, collectors_only:)
        @reader = reader
        @volume_resolver = volume_resolver
        @collectors_only = collectors_only
      end

      def section_data
        @collectors_only ? external_data : local_data
      end

      # Per-role fallback chains: most specific .env var wins, then we degrade
      # to broader-privilege siblings so a single-token stack still produces a
      # usable config while a privilege-separated stack round-trips losslessly.
      TOKEN_FALLBACKS = {
        'token_admin' => %w[INFLUX_ADMIN_TOKEN INFLUX_TOKEN DOCKER_INFLUXDB_INIT_ADMIN_TOKEN
                            INFLUX_TOKEN_READWRITE INFLUX_TOKEN_WRITE INFLUX_TOKEN_READ],
        'token_readwrite' => %w[INFLUX_TOKEN_READWRITE INFLUX_ADMIN_TOKEN INFLUX_TOKEN
                                INFLUX_TOKEN_WRITE DOCKER_INFLUXDB_INIT_ADMIN_TOKEN],
        'token_write' => %w[INFLUX_TOKEN_WRITE INFLUX_TOKEN_READWRITE INFLUX_TOKEN
                            INFLUX_ADMIN_TOKEN DOCKER_INFLUXDB_INIT_ADMIN_TOKEN],
        'token_read' => %w[INFLUX_TOKEN_READ INFLUX_TOKEN_READWRITE INFLUX_TOKEN
                           INFLUX_TOKEN_WRITE INFLUX_ADMIN_TOKEN
                           DOCKER_INFLUXDB_INIT_ADMIN_TOKEN],
      }.freeze
      private_constant :TOKEN_FALLBACKS

      private

      def local_data
        tokens = ConfigSchema::INFLUXDB_TOKEN_FIELDS.index_with { |field| token_for(field) }
        image_data_for('influxdb').merge(
          'password' => env_first('INFLUX_PASSWORD', 'DOCKER_INFLUXDB_INIT_PASSWORD'),
          'org' => env_first('INFLUX_ORG', 'DOCKER_INFLUXDB_INIT_ORG'),
          'bucket' => env_first('INFLUX_BUCKET', 'DOCKER_INFLUXDB_INIT_BUCKET'),
          'use_hashed_tokens' => @reader.raw_env['INFLUXD_USE_HASHED_TOKENS'],
          'publish_port' => publish_port,
          'host_port' => host_port,
        ).merge(tokens).merge(@volume_resolver.path_data('influxdb')).compact
      end

      # The donor's port mapping for the InfluxDB UI, if any. Returns nil if
      # nothing on the influxdb service publishes container port 8086.
      def published_port_mapping
        Array(@reader.service('influxdb')&.dig('ports')).find { |entry| targets_influxdb?(entry) }
      end

      # True when the donor's compose publishes InfluxDB's port 8086 to the
      # host (covering UI, HTTP API, and external tooling). Returns nil
      # otherwise so .compact drops the key and the default (don't publish)
      # takes over.
      def publish_port
        published_port_mapping ? true : nil
      end

      # Host-side port the donor maps to the InfluxDB UI. Returns nil for the
      # canonical 8086 (default — no need to persist) and for mappings
      # without an explicit host port (e.g. bare "8086", which docker assigns
      # an ephemeral host port to). Anything else is preserved so a remapped
      # port like 18086:8086 survives the round-trip.
      def host_port
        mapping = published_port_mapping
        return nil unless mapping

        host = published_host_port(mapping)
        host if host && host != INFLUXDB_CONTAINER_PORT.to_s
      end

      # `docker compose config --format json` normalizes short-form ports to
      # long-form hashes (target/published/protocol). Handle both so a
      # raw-YAML fallback path stays compatible too.
      def targets_influxdb?(entry)
        case entry
        when Hash then entry['target'].to_i == INFLUXDB_CONTAINER_PORT
        else entry.to_s.split(':').last == INFLUXDB_CONTAINER_PORT.to_s
        end
      end

      def published_host_port(entry)
        case entry
        when Hash then entry['published']&.to_s
        else
          host, container = entry.to_s.split(':', 2)
          container ? host : nil
        end
      end

      def external_data
        {
          'host' => @reader.raw_env['INFLUX_HOST'],
          'port' => @reader.raw_env['INFLUX_PORT'],
          'schema' => @reader.raw_env['INFLUX_SCHEMA'],
          'org' => @reader.raw_env['INFLUX_ORG'],
          'bucket' => @reader.raw_env['INFLUX_BUCKET'],
          'token_write' => token_for('token_write'),
        }.compact
      end

      def token_for(role)
        env_first(*TOKEN_FALLBACKS.fetch(role))
      end
    end
  end
end
