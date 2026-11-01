module Import
  class ConfigurationImporter
    class PublicDataCollectorExtractor
      include Helpers

      def initialize(reader)
        @reader = reader
      end

      def section_data
        return unless @reader.service('public-data-collector')

        # SystemExtractor takes COUNTRY, ENABLE_FUEL follows on export.
        image_data_for('public-data-collector')
      end
    end
  end
end
