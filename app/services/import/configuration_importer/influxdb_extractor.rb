module Import
  class ConfigurationImporter
    class InfluxdbExtractor
      include Helpers

      # Container port the InfluxDB UI always listens on.
      INFLUXDB_CONTAINER_PORT = 8086

      # The `influxdb` entrypoint of a reverse proxy, which carries the port
      # where no mapping of the service does.
      ENTRYPOINT_ADDRESS = /\A--entrypoints\.influxdb\.address=\S*?:(\d+)\z/i

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
      # `DOCKER_INFLUXDB_INIT_ADMIN_TOKEN` outranks generic `INFLUX_TOKEN` for
      # admin/rw/write (init var explicitly names the admin token) but not for
      # read — a donor with only `INFLUX_TOKEN=read-token` is signaling a read
      # role, not an admin one.
      TOKEN_FALLBACKS = {
        'token_admin' => %w[INFLUX_ADMIN_TOKEN DOCKER_INFLUXDB_INIT_ADMIN_TOKEN
                            INFLUX_TOKEN INFLUX_TOKEN_READWRITE INFLUX_TOKEN_WRITE
                            INFLUX_TOKEN_READ],
        'token_readwrite' => %w[INFLUX_TOKEN_READWRITE INFLUX_ADMIN_TOKEN
                                DOCKER_INFLUXDB_INIT_ADMIN_TOKEN INFLUX_TOKEN
                                INFLUX_TOKEN_WRITE],
        'token_write' => %w[INFLUX_TOKEN_WRITE INFLUX_TOKEN_READWRITE INFLUX_ADMIN_TOKEN
                            DOCKER_INFLUXDB_INIT_ADMIN_TOKEN INFLUX_TOKEN],
        'token_read' => %w[INFLUX_TOKEN_READ INFLUX_TOKEN_READWRITE INFLUX_TOKEN
                           INFLUX_TOKEN_WRITE INFLUX_ADMIN_TOKEN
                           DOCKER_INFLUXDB_INIT_ADMIN_TOKEN],
      }.freeze
      private_constant :TOKEN_FALLBACKS

      # Canonical consumer service per role, mirroring
      # app/services/export/services/*.rb. Lets the importer pick up role
      # tokens that donors wire per-service via custom env names (e.g.
      # `INFLUX_TOKEN: ${POWER_SPLITTER_INFLUX_TOKEN}` on power-splitter).
      ROLE_CONSUMERS = {
        'token_admin' => %w[influxdb],
        'token_readwrite' => %w[power-splitter],
        'token_write' => %w[mqtt-collector senec-collector shelly-collector
                            forecast-collector ingest],
        'token_read' => %w[dashboard],
      }.freeze
      private_constant :ROLE_CONSUMERS

      private

      def local_data
        tokens = ConfigSchema::INFLUXDB_TOKEN_FIELDS.index_with { |field| token_for(field) }
        image_data_for('influxdb').merge(
          'password' => env_first('INFLUX_PASSWORD', 'DOCKER_INFLUXDB_INIT_PASSWORD', inline: 'influxdb'),
          'org' => env_first('INFLUX_ORG', 'DOCKER_INFLUXDB_INIT_ORG', inline: 'influxdb'),
          'bucket' => env_first('INFLUX_BUCKET', 'DOCKER_INFLUXDB_INIT_BUCKET', inline: 'influxdb'),
          'use_hashed_tokens' => @reader.raw_env['INFLUXD_USE_HASHED_TOKENS'],
          'publish_port' => publish_port,
          'host_port' => host_port,
        ).merge(tokens).merge(@volume_resolver.path_data('influxdb')).compact
      end

      # The imported port mapping for the InfluxDB UI, if any. Returns nil
      # if nothing on the influxdb service publishes container port 8086.
      def published_port_mapping
        Array(@reader.service('influxdb')&.dig('ports')).find { |entry| targets_influxdb?(entry) }
      end

      # True when the imported stack makes InfluxDB reachable from outside the
      # Docker network: it publishes port 8086 to the host (covering UI, HTTP
      # API and external tooling), or a reverse proxy routes it. Returns nil
      # otherwise so .compact drops the key and the default (don't publish)
      # takes over.
      def publish_port
        published_port_mapping || routed_by_proxy? ? true : nil
      end

      # Whether a router of a reverse proxy names InfluxDB. A stack routed that
      # way publishes no host port for it, so the port mapping says nothing,
      # yet the database is reachable and has to stay so after the export
      # (see Export::Services::Influxdb.exposed?).
      def routed_by_proxy?
        labels = @reader.service('influxdb').to_h.then do |service|
          [service['labels'], service.dig('deploy', 'labels')].compact
        end

        labels.flat_map { |set| set.is_a?(Hash) ? set.keys : Array(set).map(&:to_s) }
              .any? { |label| label.match?(/\Atraefik\.http\.routers\./i) }
      end

      # Host-side port the imported compose maps to the InfluxDB UI. Returns nil for the
      # canonical 8086 (default — no need to persist) and for mappings
      # without an explicit host port (e.g. bare "8086", which docker assigns
      # an ephemeral host port to). Anything else is preserved so a remapped
      # port like 18086:8086 survives the round-trip.
      def host_port
        mapping = published_port_mapping
        return entrypoint_port unless mapping

        host = published_host_port(mapping)
        host if host && host != INFLUXDB_CONTAINER_PORT.to_s
      end

      # Where a reverse proxy routes InfluxDB, the port lives on that proxy's
      # `influxdb` entrypoint rather than on a mapping of the service. HELIOS
      # writes that entrypoint from this field on the next export, so a port
      # that is not the canonical one has to arrive here.
      def entrypoint_port
        port = Array(@reader.service('traefik')&.dig('command'))
               .filter_map { |arg| arg.to_s[ENTRYPOINT_ADDRESS, 1] }
               .first

        port if port && port != INFLUXDB_CONTAINER_PORT.to_s
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

      # Role-specific .env key wins ahead of consumer_token so a donor stack
      # with a properly set INFLUX_TOKEN_WRITE in .env beats per-service inline
      # placeholders (e.g. anonymization residue like `INFLUX_TOKEN=XXXXX`).
      def token_for(role)
        fallbacks = TOKEN_FALLBACKS.fetch(role)
        @reader.raw_env[fallbacks.first].presence ||
          consumer_token(role) ||
          env_first(*fallbacks, inline: 'influxdb')
      end

      def consumer_token(role)
        ROLE_CONSUMERS.fetch(role, []).lazy.filter_map { |s| service_env(s)['INFLUX_TOKEN'].presence }.first
      end
    end
  end
end
