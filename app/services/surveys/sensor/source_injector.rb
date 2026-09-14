module Surveys
  module Sensor
    # Builds the source question of the sensor survey: which sources this
    # sensor can read through, and which of them are actually on offer.
    #
    # Only a source that is set up can be picked, so a sensor never brings one
    # into being. That decision is made on the data sources screen alone (see
    # Configuration#offered_sources).
    class SourceInjector
      # Source choice texts, each a localized "label\n\ndescription" string.
      # The survey frontend renders the part after the blank line as a muted
      # hint.
      TEXTS = {
        'senec' => Base.localized(
          en: "SENEC Collector\n\nRuns as its own service and reads the measurement directly from the SENEC system.",
          de: "SENEC-Collector\n\nLäuft als eigener Dienst und liest den Messwert direkt aus dem SENEC-System.",
        ),
        'shelly' => Base.localized(
          en: "Shelly Collector\n\nRuns as its own service and reads the measurement directly from the Shelly meter.",
          de: "Shelly-Collector\n\nLäuft als eigener Dienst und liest den Messwert direkt vom Shelly-Stromzähler.",
        ),
        'mqtt' => Base.localized(
          en: "MQTT Collector\n\nRuns as its own service and subscribes to a topic on an MQTT broker.",
          de: "MQTT-Collector\n\nLäuft als eigener Dienst und abonniert ein Topic von einem MQTT-Broker.",
        ),
        'forecast' => Base.localized(
          en: "Forecast Collector\n\nRuns as its own service and queries PVNode, forecast.solar, or Solcast directly.",
          de: "Forecast-Collector\n\nLäuft als eigener Dienst und fragt pvnode, forecast.solar oder Solcast direkt ab.",
        ),
        'external' => Base.localized(
          en: "External\n\nAnother software, such as Home Assistant or ioBroker, " \
              'writes the measurement into InfluxDB externally.',
          de: "Extern\n\nEine andere Software (z.B. Home Assistant oder ioBroker) " \
              'schreibt den Messwert von außen in die InfluxDB.',
        ),
      }.freeze

      def initialize(sensor_name)
        @sensor_name = sensor_name
      end

      def call(survey)
        sources = SensorRegistry.sources_for(sensor_name)
        sources &= Configuration::DASHBOARD_ONLY_SOURCES if configuration.dashboard_only?
        offered = sources.select { |source| offer?(source) }
        return if offered.empty?

        element = find_source_element(survey)
        return unless element

        element['choices'] = offered.map { |source| { 'value' => source, 'text' => TEXTS[source] || source } }
        element['description'] = hint(dropped: sources.size > offered.size)
      end

      private

      attr_reader :sensor_name

      def find_source_element(survey)
        survey['pages'].flat_map { |page| page['elements'] || [] }.find { |element| element['name'] == 'source' }
      end

      # The source a sensor already reads through stays on the list whatever
      # its state, or opening the survey would silently drop it.
      def offer?(source)
        configuration.source_available?(source) || source == current_source
      end

      def current_source
        @current_source ||= configuration.sensor_config(sensor_name).source
      end

      # Named so that missing choices do not look like a defect. Dashboard-only
      # mode has a reason of its own and states that instead.
      def hint(dropped:)
        return dashboard_only_hint if configuration.dashboard_only?
        return unless dropped

        Base.localized(
          en: 'Further sources appear here once they are switched on under Data Sources.',
          de: 'Weitere Quellen erscheinen hier, sobald sie unter Datenquellen eingeschaltet sind.',
        )
      end

      def dashboard_only_hint
        Base.localized(
          en: 'In dashboard-only mode, device collectors (Shelly, SENEC, MQTT) run ' \
              'on a separate HELIOS installation and are not available here.',
          de: 'In diesem Betriebsmodus laufen Geräte-Kollektoren (Shelly, SENEC, MQTT) ' \
              'auf einer separaten HELIOS-Installation und sind hier nicht verfügbar.',
        )
      end

      def configuration
        @configuration ||= Configuration.current
      end
    end
  end
end
