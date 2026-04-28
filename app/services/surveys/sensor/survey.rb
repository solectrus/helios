module Surveys
  module Sensor
    # Tailors the generic sensor survey to a specific sensor: filters the
    # source choices, locks measurement/field for fixed-source collectors,
    # and injects optional pages based on what the sensor supports.
    class Survey < Base
      SOURCE_LABELS = {
        'senec' => localized(en: 'SENEC Collector', de: 'SENEC-Collector'),
        'shelly' => localized(en: 'Shelly Collector', de: 'Shelly-Collector'),
        'mqtt' => localized(en: 'MQTT Collector', de: 'MQTT-Collector'),
        'forecast' => localized(en: 'Forecast Collector', de: 'Forecast-Collector'),
        'external' => localized(en: 'External', de: 'Extern'),
      }.freeze

      private

      def valid?
        sensor_name.present? && SensorRegistry.valid?(sensor_name)
      end

      def customize!(data)
        inject_sensor_title!(data)
        inject_source_choices!(data)
        MappingInjector.new(sensor_name).call(data)
        inject_name_page!(data) if custom_power_sensor?
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
        data['title'] = sensor_name.upcase
      end

      def inject_source_choices!(data)
        sources = SensorRegistry.sources_for(sensor_name)
        return if sources.empty?

        element = find_element(data, 'source')
        return unless element

        element['choices'] = sources.map { |s| source_choice(s) }
      end

      def source_choice(source)
        { 'value' => source, 'text' => SOURCE_LABELS[source] || source }
      end

      def inject_name_page!(data)
        name_page = {
          'name' => 'p_name',
          'title' => self.class.localized(en: 'Display name', de: 'Anzeigename'),
          'elements' => [name_element],
        }
        data['pages'].insert(1, name_page)
      end

      def name_element
        {
          'type' => 'text',
          'name' => 'name',
          'title' => self.class.localized(
            en: 'Name for this consumer',
            de: 'Name für diesen Verbraucher',
          ),
          'description' => self.class.localized(
            en: 'Displayed as label in the dashboard',
            de: 'Wird im Dashboard als Bezeichnung angezeigt',
          ),
          'isRequired' => true,
          'placeholder' => self.class.localized(en: 'e.g. Fridge', de: 'z.B. Kühlschrank'),
        }
      end

      def inject_shelly_connection_page!(data)
        shelly = Configuration.current.shelly
        remove_page = shelly&.connection == 'cloud' ? 'p_shelly_local' : 'p_shelly_cloud'
        data['pages']&.reject! { |p| p['name'] == remove_page }
      end

      def inject_shelly_invert_power!(data)
        shelly_local_page = find_page(data, 'p_shelly_local')
        return unless shelly_local_page

        shelly_local_page['elements'] << {
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
          'elements' => [house_power_element],
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
          'description' => self.class.localized(
            en: "Corrects house power by deducting this sensor's consumption",
            de: 'Korrigiert den Hausverbrauch, indem der Verbrauch dieses Sensors abgezogen wird',
          ),
          'defaultValue' => false,
        }
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
