module Surveys
  module Software
    # Central image-channel chooser plus Watchtower poll interval. The matrix
    # row set depends on which services are active (see PREDICATES), so it's
    # built dynamically and prepended to the static update-interval question
    # shipped in the JSON sidecar.
    class Survey < Base
      # `active?` predicate per surveyed service. Keys double as matrix row
      # values and must exist in `Configuration::SOFTWARE_SERVICES`, which
      # supplies the registry — a service is offered only when its predicate
      # holds and its registry exposes more than one channel.
      PREDICATES = {
        'dashboard' => ->(c) { !c.collectors_only? },
        'senec_collector' => ->(c) { c.active_sources.include?('senec') },
        'shelly_collector' => ->(c) { c.active_sources.include?('shelly') },
        'mqtt_collector' => ->(c) { c.active_sources.include?('mqtt') },
        'forecast_collector' => ->(c) { c.active_sources.include?('forecast') },
        'tibber_collector' => ->(c) { Export::Services::TibberCollector.enabled?(c) },
        'senec_charger' => ->(c) { Export::Services::SenecCharger.enabled?(c) },
        'ingest' => ->(c) { c.ingest_required? },
        'power_splitter' => ->(c) { Export::Services::PowerSplitter.enabled?(c) },
        'helios' => ->(c) { Export::Services::Helios.enabled?(c) },
      }.freeze

      SERVICE_LABELS = {
        'dashboard' => { de: 'Dashboard', en: 'Dashboard' },
        'senec_collector' => { de: 'SENEC-Collector', en: 'SENEC Collector' },
        'shelly_collector' => { de: 'Shelly-Collector', en: 'Shelly Collector' },
        'mqtt_collector' => { de: 'MQTT-Collector', en: 'MQTT Collector' },
        'forecast_collector' => { de: 'Forecast-Collector', en: 'Forecast Collector' },
        'tibber_collector' => { de: 'Tibber-Collector', en: 'Tibber Collector' },
        'senec_charger' => { de: 'SENEC-Charger', en: 'SENEC Charger' },
        'ingest' => { de: 'Ingest', en: 'Ingest' },
        'power_splitter' => { de: 'Power Splitter', en: 'Power Splitter' },
        'helios' => { de: 'HELIOS', en: 'HELIOS' },
      }.freeze

      private

      def customize!(data)
        rows = build_matrix_rows
        return if rows.empty?

        data['pages'].unshift('name' => 'p_channels', 'elements' => [matrix_element(rows)])
      end

      def build_matrix_rows
        config = Configuration.current
        PREDICATES.filter_map do |key, predicate|
          next unless predicate.call(config)

          registry = Configuration::SOFTWARE_SERVICES.fetch(key)[:registry]
          next unless DockerImages.choices(registry)

          { 'value' => key, 'text' => self.class.localized(**SERVICE_LABELS.fetch(key)) }
        end
      end

      def matrix_element(rows)
        {
          'type' => 'matrix',
          'name' => 'service_channels',
          'title' => matrix_title,
          'description' => matrix_description,
          'columns' => channel_columns,
          'rows' => rows,
          'isAllRowRequired' => true,
          'defaultValue' => rows.to_h { |r| [r['value'], 'latest'] },
        }
      end

      def matrix_title
        self.class.localized(
          de: 'Auf welchem Kanal möchtest du pro Dienst sein?',
          en: 'Which channel do you want each service to follow?',
        )
      end

      def matrix_description
        self.class.localized(
          de: 'Stabil: nur stabile Versionen, Updates kommen in größeren zeitlichen ' \
              'Abständen. Entwicklung: Entwickler-Versionen, Updates kommen täglich ' \
              'mehrfach — nur in begründeten Fällen wählen.',
          en: 'Stable: only stable releases, updates ship at longer intervals. ' \
              'Development: developer builds, updates land multiple times per day — ' \
              'pick only for a specific reason.',
        )
      end

      def channel_columns
        [
          { 'value' => 'latest', 'text' => self.class.localized(de: 'Stabil', en: 'Stable') },
          { 'value' => 'develop', 'text' => self.class.localized(de: 'Entwicklung', en: 'Development') },
        ]
      end
    end
  end
end
