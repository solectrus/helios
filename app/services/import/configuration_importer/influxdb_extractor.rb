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

      private

      def local_data
        image_data_for('influxdb').merge(
          'password' => env_first('INFLUX_PASSWORD', 'DOCKER_INFLUXDB_INIT_PASSWORD'),
          'org' => env_first('INFLUX_ORG', 'DOCKER_INFLUXDB_INIT_ORG'),
          'bucket' => env_first('INFLUX_BUCKET', 'DOCKER_INFLUXDB_INIT_BUCKET'),
          'token' => token,
          'use_hashed_tokens' => @reader.raw_env['INFLUXD_USE_HASHED_TOKENS'],
        ).merge(@volume_resolver.path_data('influxdb')).compact
      end

      def external_data
        {
          'host' => @reader.raw_env['INFLUX_HOST'],
          'port' => @reader.raw_env['INFLUX_PORT'],
          'schema' => @reader.raw_env['INFLUX_SCHEMA'],
          'org' => @reader.raw_env['INFLUX_ORG'],
          'bucket' => @reader.raw_env['INFLUX_BUCKET'],
          'token' => token,
        }.compact
      end

      def token
        env_first('INFLUX_TOKEN', 'INFLUX_ADMIN_TOKEN', 'INFLUX_TOKEN_WRITE', 'DOCKER_INFLUXDB_INIT_ADMIN_TOKEN')
      end
    end
  end
end
