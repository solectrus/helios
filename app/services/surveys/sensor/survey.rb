module Surveys
  module Sensor
    # Source choice texts, each a localized "label\n\ndescription" string. The
    # survey frontend renders the part after the blank line as a muted hint.
    SOURCE_TEXTS = {
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

    # The label names the sensor within HELIOS only. The SOLECTRUS dashboard
    # carries its own name for the same sensor.
    LABEL_ELEMENT = {
      'type' => 'text',
      'name' => 'name',
      'title' => Base.localized(en: 'Label for this sensor', de: 'Bezeichnung für diesen Sensor'),
      'description' => Base.localized(
        en: 'Only used inside HELIOS. The name in the SOLECTRUS dashboard is set there separately.',
        de: 'Gilt nur innerhalb von HELIOS. Die Bezeichnung im SOLECTRUS-Dashboard wird dort separat eingestellt.',
      ),
      'placeholder' => Base.localized(en: 'e.g. Fridge', de: 'z.B. Kühlschrank'),
    }.freeze
    private_constant :LABEL_ELEMENT

    # Custom sensors are part of the house power by default; deducting them
    # promotes them to their own segment in the energy flow.
    CUSTOM_HINT_EN = <<~HTML.freeze
      <p>Normally <strong>No</strong> is the right choice here: the sensor
      measures a consumer inside the house, and its consumption is already
      part of the house power.</p>
      <p><strong>Yes</strong> is only for the rare case that this consumer
      should deliberately not count as house power, for example a separately
      billed granny flat. Its measured consumption is then deducted from the
      house power and shown as a separate segment in the energy flow.</p>
    HTML
    private_constant :CUSTOM_HINT_EN

    CUSTOM_HINT_DE = <<~HTML.freeze
      <p>Normalerweise ist hier <strong>Nein</strong> richtig: Der Sensor
      misst einen Verbraucher im Haus, dessen Verbrauch ohnehin zum
      Hausverbrauch gehört.</p>
      <p><strong>Ja</strong> ist nur für den Ausnahmefall gedacht, dass
      dieser Verbraucher bewusst nicht als Hausverbrauch gelten soll, etwa
      eine separat abgerechnete Einliegerwohnung. Der gemessene Verbrauch
      wird dann vom Hausverbrauch abgezogen und erscheint als eigenes
      Segment in der Strombilanz.</p>
    HTML
    private_constant :CUSTOM_HINT_DE

    # For wallbox and heat pump the setting only decides whether their
    # consumption is double-counted in the house power.
    FIXED_HINT_EN = <<~HTML.freeze
      <p>This setting only decides whether the consumption of this consumer
      is additionally contained in the house power.</p>
      <p><strong>Yes</strong> if the house power already includes this
      consumer. The measured consumption is then deducted so that it is not
      counted twice.</p>
      <p><strong>No</strong> if the house power is measured separately and
      does not contain this consumer at all.</p>
    HTML
    private_constant :FIXED_HINT_EN

    FIXED_HINT_DE = <<~HTML.freeze
      <p>Diese Einstellung entscheidet nur, ob der Verbrauch dieses
      Verbrauchers zusätzlich im Hausverbrauch steckt.</p>
      <p><strong>Ja</strong>, wenn der Hausverbrauch diesen Verbraucher schon
      mitzählt. Der gemessene Verbrauch wird dann abgezogen, damit er nicht
      doppelt zählt.</p>
      <p><strong>Nein</strong>, wenn der Hausverbrauch separat gemessen wird
      und diesen Verbraucher gar nicht enthält.</p>
    HTML
    private_constant :FIXED_HINT_DE

    # Tailors the generic sensor survey to a specific sensor: filters the
    # source choices, locks measurement/field for fixed-source collectors,
    # and injects optional pages based on what the sensor supports.
    class Survey < Base
      private

      def valid?
        sensor_name.present? && SensorRegistry.valid?(sensor_name)
      end

      def customize!(data)
        inject_sensor_title!(data)
        inject_source_choices!(data)
        MqttInjector.new(sensor_name).call(data)
        MappingInjector.new(sensor_name).call(data)
        inject_label_page!(data) if custom_power_sensor?
        inject_shelly_connection_page!(data)
        inject_shelly_invert_power!(data) if invert_power_relevant?
        inject_house_power_page!(data) if exclude_from_house_power_relevant?
        inject_balcony_page!(data) if balcony_relevant?
      end

      def custom_power_sensor?
        sensor_name&.start_with?('custom_power_')
      end

      def invert_power_relevant?
        sensor_name&.start_with?('battery_') || sensor_name == 'inverter_power'
      end

      def exclude_from_house_power_relevant?
        sensor_name.in?(%w[heatpump_power wallbox_power]) || custom_power_sensor?
      end

      def balcony_relevant?
        SensorRegistry::BALCONY_CAPABLE_SENSORS.include?(sensor_name)
      end

      def inject_sensor_title!(data)
        data['title'] = self.class.localized(
          en: I18n.t("sensors.#{sensor_name}", locale: :en),
          de: I18n.t("sensors.#{sensor_name}", locale: :de),
        )
        data['description'] = sensor_name.upcase
      end

      def inject_source_choices!(data)
        sources = SensorRegistry.sources_for(sensor_name)
        sources &= Configuration::DASHBOARD_ONLY_SOURCES if Configuration.current.dashboard_only?
        return if sources.empty?

        element = find_element(data, 'source')
        return unless element

        element['choices'] = sources.map { |s| source_choice(s) }
        element['description'] = dashboard_only_source_hint if Configuration.current.dashboard_only?
      end

      def dashboard_only_source_hint
        self.class.localized(
          en: 'In dashboard-only mode, device collectors (Shelly, SENEC, MQTT) run ' \
              'on a separate HELIOS installation and are not available here.',
          de: 'In diesem Betriebsmodus laufen Geräte-Kollektoren (Shelly, SENEC, MQTT) ' \
              'auf einer separaten HELIOS-Installation und sind hier nicht verfügbar.',
        )
      end

      def source_choice(source)
        { 'value' => source, 'text' => source_text(source) }
      end

      def source_text(source)
        SOURCE_TEXTS[source] || source
      end

      def inject_label_page!(data)
        label_page = {
          'name' => 'p_name',
          'title' => self.class.localized(en: 'Label', de: 'Bezeichnung'),
          'elements' => [LABEL_ELEMENT],
        }
        data['pages'].insert(1, label_page)
      end

      def inject_shelly_connection_page!(data)
        shelly = Configuration.current.shelly
        remove_page = shelly&.connection == 'cloud' ? 'p_shelly_local' : 'p_shelly_cloud'
        data['pages']&.reject! { |p| p['name'] == remove_page }
      end

      def inject_shelly_invert_power!(data)
        shelly_local_page = find_page(data, 'p_shelly_local')
        return unless shelly_local_page

        # Keep the connection-test button as the page's last element.
        elements = shelly_local_page['elements']
        test_index = elements.index { |e| e['name'] == 'shelly_connection_test' }
        position = test_index || elements.length
        elements.insert(position, shelly_invert_power_element)
      end

      def shelly_invert_power_element
        {
          'type' => 'boolean',
          'name' => 'shelly_invert_power',
          'title' => self.class.localized(
            en: 'Invert power values',
            de: 'Leistungswerte invertieren',
          ),
          'description' => self.class.localized(
            en: 'Enable if power values are reported with negative sign',
            de: 'Aktiviere dies, wenn die Leistungswerte mit negativem Vorzeichen gemeldet werden',
          ),
          'defaultValue' => false,
        }
      end

      def inject_house_power_page!(data)
        data['pages'] << {
          'name' => 'p_house_power',
          'visibleIf' => "{source} = 'shelly' or {source} = 'mqtt' or {source} = 'external'",
          'title' => self.class.localized(en: 'House power', de: 'Hausverbrauch'),
          'elements' => [house_power_hint_element, house_power_element],
        }
      end

      def house_power_hint_element
        {
          'type' => 'html',
          'name' => 'house_power_hint',
          'html' =>
            if custom_power_sensor?
              self.class.localized(en: CUSTOM_HINT_EN, de: CUSTOM_HINT_DE)
            else
              self.class.localized(en: FIXED_HINT_EN, de: FIXED_HINT_DE)
            end,
        }
      end

      def house_power_element
        {
          'type' => 'boolean',
          'name' => 'exclude_from_house_power',
          'title' => self.class.localized(
            en: 'Deduct from house power',
            de: 'Aus Hausverbrauch herausrechnen',
          ),
          'description' => house_power_description,
          'defaultValue' => false,
        }
      end

      def house_power_description
        if custom_power_sensor?
          self.class.localized(
            en: "Only in exceptional cases: deducts this sensor's consumption from the house power",
            de: 'Nur in Ausnahmefällen: Zieht den Verbrauch dieses Sensors vom Hausverbrauch ab',
          )
        else
          self.class.localized(
            en: 'Prevents double counting if the house power already includes this consumer',
            de: 'Verhindert doppelte Zählung, wenn der Hausverbrauch diesen Verbraucher schon enthält',
          )
        end
      end

      def inject_balcony_page!(data)
        balcony_page = {
          'name' => 'p_balcony',
          'visibleIf' => "{source} <> 'senec'",
          'title' => self.class.localized(en: 'Balcony power plant', de: 'Steckersolargerät'),
          'elements' => [balcony_element],
        }
        mapping_index = data['pages'].index { |p| p['name'] == 'p_mapping' } || data['pages'].length
        data['pages'].insert(mapping_index, balcony_page)
      end

      def balcony_element
        {
          'type' => 'boolean',
          'name' => 'is_balcony',
          'title' => self.class.localized(
            en: 'This is a balcony power plant',
            de: 'Das ist ein Steckersolargerät (BKW)',
          ),
          'description' => balcony_description,
          'defaultValue' => false,
        }
      end

      def balcony_description
        self.class.localized(
          en: 'Balcony power plants feed directly into the home grid and distort the ' \
              'house_power reported by the inverter. This enables the Ingest service, ' \
              'which recalculates house_power correctly.',
          de: 'Balkonkraftwerke speisen direkt ins Hausnetz ein und verfälschen den vom ' \
              'Wechselrichter gemeldeten Hausverbrauch. Mit dieser Option wird der Ingest-Dienst ' \
              'aktiviert, der den Hausverbrauch korrekt neu berechnet.',
        )
      end
    end
  end
end
