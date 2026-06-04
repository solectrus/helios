module Import
  class ConfigurationImporter
    # Captures HELIOS's own image so an adopted stack keeps its release channel
    # (e.g. `:develop`) instead of being reset to the default on re-export.
    class HeliosExtractor
      include Helpers

      def initialize(reader)
        @reader = reader
      end

      def section_data
        image_data_for('helios')
      end
    end
  end
end
