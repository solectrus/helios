module Import
  class ConfigurationImporter
    class PowerSplitterExtractor
      include Helpers

      def initialize(reader)
        @reader = reader
      end

      def section_data
        return unless @reader.service('power-splitter')

        # POWER_SPLITTER_INTERVAL is fixed at 300s by HELIOS and not imported.
        image_data_for('power-splitter').compact
      end
    end
  end
end
