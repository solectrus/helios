module Import
  class ConfigurationImporter
    class InfluxdbExtractor
      include Helpers

      def initialize(reader, volume_resolver, collectors_only:)
        @reader = reader
        @volume_resolver = volume_resolver
        @collectors_only = collectors_only
      end

      def section_data
        @collectors_only ? external_data : local_data
      end

      # Per-role fallback chains: most specific .env var wins, then we degrade
      # to broader-privilege siblings so a single-token donor still produces a
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
        ).merge(tokens).merge(@volume_resolver.path_data('influxdb')).compact
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
