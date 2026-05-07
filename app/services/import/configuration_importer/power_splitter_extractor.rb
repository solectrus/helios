module Import
  class ConfigurationImporter
    class PowerSplitterExtractor
      include Helpers

      def initialize(reader)
        @reader = reader
      end

      def section_data
        return unless @reader.service('power-splitter')

        ps_env = service_env('power-splitter')
        image_data_for('power-splitter').merge(
          'interval' => ps_env['POWER_SPLITTER_INTERVAL'],
        ).compact
      end
    end
  end
end
