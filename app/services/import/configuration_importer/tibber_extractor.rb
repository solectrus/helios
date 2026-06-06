module Import
  class ConfigurationImporter
    class TibberExtractor
      include Helpers

      def initialize(reader)
        @reader = reader
      end

      def enabled?
        @reader.services.key?('tibber-collector')
      end

      def section_data
        return unless enabled?

        tibber_env = service_env('tibber-collector')
        data = {
          'token' => tibber_env['TIBBER_TOKEN'],
          # Read the measurement from the resolved service env so indirections
          # like INFLUX_MEASUREMENT=${INFLUX_MEASUREMENT_PRICES} (or the legacy
          # INFLUX_MEASUREMENT_TIBBER name seen in the wild) round-trip to the
          # canonical INFLUX_MEASUREMENT_PRICES on re-export. The collector
          # itself defaults to 'Prices' when unset.
          'measurement' => tibber_env['INFLUX_MEASUREMENT'].presence,
        }.compact.presence
        # The image carries the pinned release channel, so it is captured to
        # round-trip on re-export — without it, adopting a stack would move a
        # pinned collector onto the DockerImages default. Only added to a
        # section that exists: an image alone never configures the collector.
        data&.merge(image_data_for('tibber-collector'))
      end
    end
  end
end
