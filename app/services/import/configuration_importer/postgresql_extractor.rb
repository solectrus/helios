module Import
  class ConfigurationImporter
    class PostgresqlExtractor
      include Helpers

      def initialize(reader, volume_resolver)
        @reader = reader
        @volume_resolver = volume_resolver
      end

      def section_data
        image_data_for('postgresql').merge(
          'password' => env_first('POSTGRES_PASSWORD', 'POSTGRES_ADMIN_PASSWORD'),
          'pgdata' => @reader.raw_env['PGDATA'],
        ).merge(@volume_resolver.path_data('postgresql')).compact
      end
    end
  end
end
