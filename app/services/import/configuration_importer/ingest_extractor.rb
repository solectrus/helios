module Import
  class ConfigurationImporter
    class IngestExtractor
      include Helpers

      def initialize(reader, volume_resolver, balcony_detector)
        @reader = reader
        @volume_resolver = volume_resolver
        @balcony_detector = balcony_detector
      end

      def section_data
        return unless @balcony_detector.sensor_name

        ingest_env = service_env('ingest')
        image_data_for('ingest').merge(
          'retention_hours' => ingest_env['RETENTION_HOURS'],
        ).merge(@volume_resolver.path_data('ingest')).compact
      end
    end
  end
end
