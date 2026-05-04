module Import
  class ConfigurationImporter
    class RedisExtractor
      include Helpers

      def initialize(reader, volume_resolver)
        @reader = reader
        @volume_resolver = volume_resolver
      end

      def section_data
        image_data_for('redis').merge(@volume_resolver.path_data('redis')).compact
      end
    end
  end
end
