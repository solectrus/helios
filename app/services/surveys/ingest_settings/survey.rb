module Surveys
  module IngestSettings
    # Adds the write address to the Ingest settings, together with the values
    # an external source still has to redirect. The sensor list carries the
    # same hint per sensor (SensorRow::Component); here it answers the question
    # "where do I send this?" without opening a sensor first.
    class Survey < Base
      private

      # The address only means something while the service runs, so a switched
      # off recalculation shows the switch alone. SurveyJS decides that, not
      # the server: the switch changes without a reload, and a server-side gate
      # would leave the address standing until the survey is opened again.
      def customize!(data)
        page = find_page(data, 'p_settings')
        return unless page && configuration.ingest_offered?

        page['elements'].insert(1, endpoint_element)
      end

      def endpoint_element
        {
          'type' => 'html',
          'name' => 'ingest_endpoint',
          'visibleIf' => '{active} = true',
          'html' => endpoint_html,
        }
      end

      def endpoint_html
        self.class.localized(
          en: "<p><strong>#{address_en}</strong></p><p>#{external_sensors_en}</p>",
          de: "<p><strong>#{address_de}</strong></p><p>#{external_sensors_de}</p>",
        )
      end

      # Nothing in the configuration names the machine (an imported stack
      # without APP_HOST, for example), so the port has to do.
      def address_en
        return "Port for external sources: <code>#{Export::IngestEndpoint::PORT}</code>" unless url

        "Address for external sources: <code>#{url}</code>"
      end

      def address_de
        return "Port für externe Quellen: <code>#{Export::IngestEndpoint::PORT}</code>" unless url

        "Adresse für externe Quellen: <code>#{url}</code>"
      end

      def url
        return @url if defined?(@url)

        raw = Export::IngestEndpoint.url(configuration)
        @url = raw && CGI.escapeHTML(raw)
      end

      def external_sensors_en
        return 'Every collector HELIOS manages writes there already.' if external_sensors.empty?

        'These values come from an external source and have to be sent there instead of to ' \
          "InfluxDB: #{sensor_labels(:en)}."
      end

      def external_sensors_de
        return 'Alle von HELIOS verwalteten Collectors schreiben bereits dorthin.' if external_sensors.empty?

        'Folgende Werte kommen aus einer externen Quelle und müssen dorthin gesendet werden statt ' \
          "in die InfluxDB: #{sensor_labels(:de)}."
      end

      def sensor_labels(locale)
        external_sensors.map { |name| CGI.escapeHTML(I18n.t("sensors.#{name}", locale:)) }.join(', ')
      end

      def external_sensors
        @external_sensors ||= configuration.external_ingest_inputs
      end

      def configuration
        @configuration ||= Configuration.current
      end
    end
  end
end
